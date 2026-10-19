import Foundation
import CoreFoundation
import Darwin

struct AuditLocation: Hashable, Sendable {
    let account: String
    let organization: String
    let session: String
    var key: String { [account, organization, session].joined(separator: "/") }
    var audit: [String] { [account, organization, session, "audit.jsonl"] }
    var metadata: [String] { [account, organization, session + ".json"] }
}

enum ClaudeAuditFiles {
    enum Failure: Error { case unsafeFile, unavailable, capacity, changed }
    static func discover(root: URL) throws -> [AuditLocation] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        func names(_ directory: URL) throws -> [String] {
            var info = stat()
            guard lstat(directory.path, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & S_IFMT == S_IFDIR else { throw Failure.unsafeFile }
            let values = try fm.contentsOfDirectory(atPath: directory.path)
            guard values.count <= 4096 else { throw Failure.capacity }
            return values.sorted()
        }
        var result: [AuditLocation] = []
        for account in try names(root) where identifier(account) && account != "skills-plugin" {
            let parent = root.appendingPathComponent(account)
            for org in try names(parent) where identifier(org) {
                for file in try names(parent.appendingPathComponent(org)) where file.hasSuffix(".json") {
                    let id = String(file.dropLast(5))
                    guard id.hasPrefix("local_"), identifier(id) else { continue }
                    guard result.count < 512 else { throw Failure.capacity }
                    result.append(.init(account: account, organization: org, session: id))
                }
            }
        }
        return result
    }
    static func identifier(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 128 && text.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    static func eligible(_ data: Data, session: String) throws -> Bool {
        guard data.count <= 512 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["sessionId"] as? String == session else { throw Failure.unsafeFile }
        if let archived = object["isArchived"] {
            guard let value = archived as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw Failure.unsafeFile }
            if value.boolValue { return false }
        }
        if let kind = object["sessionType"], !(kind is NSNull) {
            guard let kind = kind as? String else { throw Failure.unsafeFile }
            return ["chat", "code", "scheduled"].contains(kind)
        }
        return true
    }
}

/// Each path component is opened relative to an already checked directory descriptor.
/// Parent symlink swaps cannot redirect a read outside the configured native store.
final class ReadOnlyAuditFile {
    struct Info: Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let size: UInt64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let birth: TimeInterval
    }
    let descriptor: Int32
    init(root: URL, components: [String]) throws {
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            throw ClaudeAuditFiles.Failure.unsafeFile
        }
        var current = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { throw ClaudeAuditFiles.Failure.unavailable }
        defer { close(current) }
        for component in components.dropLast() {
            var info = stat()
            guard fstat(current, &info) == 0, info.st_uid == getuid() else { throw ClaudeAuditFiles.Failure.unsafeFile }
            let next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw ClaudeAuditFiles.Failure.unsafeFile }
            close(current); current = next
        }
        var parent = stat()
        guard fstat(current, &parent) == 0, parent.st_uid == getuid() else { throw ClaudeAuditFiles.Failure.unsafeFile }
        let file = openat(current, components.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else { throw ClaudeAuditFiles.Failure.unavailable }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else {
            close(file); throw ClaudeAuditFiles.Failure.unsafeFile
        }
        descriptor = file
    }
    deinit { close(descriptor) }
    func info() throws -> Info {
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_size >= 0 else { throw ClaudeAuditFiles.Failure.unavailable }
        return .init(device: value.st_dev, inode: value.st_ino, size: UInt64(value.st_size),
                     modifiedSeconds: value.st_mtimespec.tv_sec, modifiedNanoseconds: value.st_mtimespec.tv_nsec,
                     birth: Double(value.st_birthtimespec.tv_sec) + Double(value.st_birthtimespec.tv_nsec) / 1e9)
    }
    func read(offset: UInt64, count: Int) throws -> Data {
        guard count >= 0, count <= 512 * 1024, offset <= UInt64(Int64.max) else { throw ClaudeAuditFiles.Failure.capacity }
        var data = Data(count: count), received = 0
        while received < count {
            let result = data.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress!.advanced(by: received), count - received, off_t(offset) + off_t(received))
            }
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { throw ClaudeAuditFiles.Failure.changed }
            received += result
        }
        return data
    }
    func checkpoint(at offset: UInt64) throws -> Data {
        let count = Int(min(offset, 64))
        return try read(offset: offset - UInt64(count), count: count)
    }
}

struct ClaudeAuditCursor: Sendable {
    var info: ReadOnlyAuditFile.Info
    var offset: UInt64
    var checkpoint: Data
    var fragment = Data()
    var dropping = false
    var state = ClaudeAuditState()
    var metadataInfo: ReadOnlyAuditFile.Info?
    var eligible: Bool?

    init(file: ReadOnlyAuditFile, atEnd: Bool) throws {
        info = try file.info(); offset = atEnd ? info.size : 0
        checkpoint = try file.checkpoint(at: offset)
    }
    var caughtUp: Bool { offset == info.size && fragment.isEmpty && !dropping }
    mutating func read(_ file: ReadOnlyAuditFile) throws {
        let current = try file.info()
        guard current.device == info.device, current.inode == info.inode, current.size >= offset,
              try file.checkpoint(at: offset) == checkpoint else {
            self = try Self(file: file, atEnd: true); return
        }
        let count = Int(min(current.size - offset, 256 * 1024))
        let data = try file.read(offset: offset, count: count)
        let end = offset + UInt64(count)
        let expected = Data((checkpoint + data).suffix(64))
        guard try file.info().size >= end, try file.checkpoint(at: end) == expected else {
            self = try Self(file: file, atEnd: true); return
        }
        info = current; offset = end; checkpoint = expected
        var start = data.startIndex
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 10)
            let end = newline ?? data.endIndex
            if !dropping {
                if fragment.count + end - start > 512 * 1024 {
                    state.invalidate(); fragment.removeAll(keepingCapacity: false); dropping = true
                } else { fragment.append(contentsOf: data[start..<end]) }
            }
            if let newline {
                if !dropping, !fragment.isEmpty { state.consume(fragment) }
                fragment.removeAll(keepingCapacity: false); dropping = false
                start = data.index(after: newline)
            } else { break }
        }
    }
}
