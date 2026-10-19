import Foundation
import Darwin
import Testing
@testable import AgentHandlerCore

struct ProcessCrashTests {
    // Catches losing a committed reservation/outcome when the writer dies without SQLite close/deinit.
    @Test(arguments: ["reserved", "accepted", "notSent"])
    func killedWriterPreservesDeliveryContract(checkpoint: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ah-crash-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // swift-testing may run inside a toolchain helper outside the package's build directory.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = root.appendingPathComponent(".build/debug/LedgerCrashFixture")
        let child = Process()
        try #require(FileManager.default.isExecutableFile(atPath: executable.path), "SwiftPM must build the crash fixture dependency")
        child.executableURL = executable
        child.arguments = [directory.path, checkpoint]
        try child.run()
        let deadline = Date().addingTimeInterval(5)
        while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let timedOut = child.isRunning
        if timedOut { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
        #expect(!timedOut, "The fixture must reach its own committed checkpoint before it terminates")
        #expect(child.terminationReason == .uncaughtSignal)
        #expect(child.terminationStatus == SIGKILL)
        let ledger = try SQLiteLedger(url: directory.appendingPathComponent("ledger.sqlite"))
        let key = RequestKey(scope: .init(installation: "crash-fixture", conversation: "conversation"), turn: "turn", nativeID: .string("question"))
        let expected: LedgerStatus = checkpoint == "reserved" ? .uncertain : checkpoint == "accepted" ? .accepted : .notSent
        #expect(try ledger.status(for: key)?.status == expected)
        if checkpoint == "notSent" {
            try ledger.reserve(key: key, fingerprint: "changed", attemptID: UUID())
            #expect(try ledger.status(for: key)?.status == .inFlight)
        } else {
            #expect(throws: ResponseError.alreadySubmitted) { try ledger.reserve(key: key, fingerprint: "changed", attemptID: UUID()) }
        }
    }
}
