import Darwin
import Foundation

/// A short-lived official app-server connection. No threads, inference, login,
/// raw-token access or quota-reset operations. Runs away from the UI thread.
public enum CodexUsageReader {
    enum Failure: Error { case unavailable, timedOut, invalidReply }

    public static func read(executable: URL, directory: URL, timeout: TimeInterval = 12) async throws -> CodexUsageSnapshot {
        let worker = Task.detached(priority: .utility) {
            try readBlocking(executable: executable, directory: directory, timeout: timeout)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func readBlocking(executable: URL, directory: URL, timeout: TimeInterval) throws -> CodexUsageSnapshot {
        guard timeout.isFinite, timeout > 0 else { throw Failure.unavailable }
        try Task.checkCancellation()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = directory.path
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A child exiting between response and write must not terminate this app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw Failure.unavailable }
        defer {
            try? input.fileHandleForReading.close(); try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning, ProcessInfo.processInfo.systemUptime < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            if process.processIdentifier > 0 { process.waitUntilExit() }
        }
        try process.run()
        try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let fd = output.fileHandleForReading.fileDescriptor
        var pending = Data(), total = 0
        func send(_ object: [String: Any]) throws {
            try Task.checkCancellation()
            var bytes = try JSONSerialization.data(withJSONObject: object); bytes.append(10)
            try input.fileHandleForWriting.write(contentsOf: bytes)
        }
        func reply(id: Int) throws -> Data {
            while true {
                try Task.checkCancellation()
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timedOut }
                if let newline = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
                    if (object?["id"] as? Int) == id {
                        guard object?["error"] == nil, let result = object?["result"] as? [String: Any] else { throw Failure.invalidReply }
                        return try JSONSerialization.data(withJSONObject: result)
                    }
                    continue
                }
                var entry = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&entry, 1, 100)
                if ready < 0, errno == EINTR { continue }
                guard ready >= 0 else { throw Failure.unavailable }
                if ready == 0 { continue }
                var buffer = [UInt8](repeating: 0, count: 16_384)
                let size = Darwin.read(fd, &buffer, buffer.count)
                if size < 0, errno == EINTR { continue }
                guard size > 0 else { throw Failure.unavailable }
                total += size
                guard total <= 1_048_576 else { throw Failure.invalidReply }
                pending.append(contentsOf: buffer.prefix(size))
            }
        }
        try send(["id": 0, "method": "initialize", "params": ["clientInfo": [
            "name": "agent-handler", "title": "Agent Handler", "version": "0.1.0"]]])
        _ = try reply(id: 0)
        try send(["method": "initialized", "params": [:]])
        try send(["id": 1, "method": "account/rateLimits/read"])
        return try CodexUsageSnapshot.decode(reply(id: 1))
    }
}
