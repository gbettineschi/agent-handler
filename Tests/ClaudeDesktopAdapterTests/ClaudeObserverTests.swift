import Foundation
import Darwin
import Testing
import AgentHandlerCore
@testable import ClaudeDesktopAdapter

final class AuditFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-handler-claude-\(UUID().uuidString)")
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    func session(_ id: String = "local_one", account: String = "account", data: Data = Data()) throws -> URL {
        let parent = root.appendingPathComponent("\(account)/org")
        let directory = parent.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["sessionId": id, "isArchived": false])
            .write(to: parent.appendingPathComponent(id + ".json"))
        let file = directory.appendingPathComponent("audit.jsonl")
        try data.write(to: file); return file
    }
    func append(_ file: URL, _ records: [Data], newline: Bool = true) throws {
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
        try handle.seekToEnd()
        for record in records { try handle.write(contentsOf: record); if newline { try handle.write(contentsOf: Data([10])) } }
    }
    func observer() -> ClaudeDesktopObserver {
        // Explicit old observation start makes new-file tests independent of birthtime precision.
        ClaudeDesktopObserver(root: root, now: { Date(timeIntervalSince1970: 946_684_800) })
    }
}

struct ClaudeObserverTests {
    @Test func nonRegularAuditFileIsRejectedBeforeWaitingForAWriter() throws {
        let fixture = try AuditFixture(), file = try fixture.session()
        try FileManager.default.removeItem(at: file)
        #expect(mkfifo(file.path, 0o600) == 0)
        // Release a regressed blocking open, so this test reports failure instead of hanging.
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(1)) {
            let writer = open(file.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { close(writer) }
        }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            _ = try ReadOnlyAuditFile(root: fixture.root, components: ["account", "org", "local_one", "audit.jsonl"])
            Issue.record("A FIFO was accepted as an audit file")
        } catch { }
        #expect(ProcessInfo.processInfo.systemUptime - started < 0.5)
    }

    @Test func eofBaselineDiscardsTheRestOfAnUnfinishedRecord() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer()
        let file = try fixture.session(data: Data("{\"unfinished\":".utf8))
        await observer.poll(sourceInstance: "p")
        // These bytes are the suffix of the pre-existing line, not a fresh init.
        try fixture.append(file, [initLine("suffix"), resultLine("suffix-result")])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().isEmpty)
        try fixture.append(file, [initLine("fresh"), resultLine("fresh-result")])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.turnID == "fresh")
        #expect(await observer.activity().first?.status == .completed)
    }

    @Test(arguments: ["audit", "metadata"])
    func unavailableInputDiscardsPartialInitAndRequiresAnEofBaseline(input: String) async throws {
        let fixture = try AuditFixture(), observer = fixture.observer(), file = try fixture.session()
        await observer.poll(sourceInstance: "p")
        try fixture.append(file, [initLine("before-gap")])
        await observer.poll(sourceInstance: "p")
        let partial = try initLine("split-across-gap"), half = partial.count / 2
        try fixture.append(file, [Data(partial.prefix(half))], newline: false)
        await observer.poll(sourceInstance: "p")
        let target = input == "audit" ? file : file.deletingLastPathComponent().appendingPathExtension("json")
        let saved = target.appendingPathExtension("saved")
        try FileManager.default.moveItem(at: target, to: saved)
        // A directory keeps discovery stable while a regular-file open fails.
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        await observer.poll(sourceInstance: "p")
        await observer.poll(sourceInstance: "p") // Repeated failures must preserve the baseline requirement.
        try FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: saved, to: target)
        try fixture.append(file, [Data(partial.dropFirst(half)), resultLine("gap-result")])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [initLine("after-gap"), resultLine("after-gap-result")])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.turnID == "after-gap")
        #expect(await observer.activity().first?.status == .completed)
    }

    @Test func existingHistoryIsBaselinedAndOnlyNewInitCanComplete() async throws {
        let fixture = try AuditFixture()
        let file = try fixture.session()
        try fixture.append(file, [initLine(), resultLine()])
        let observer = fixture.observer()
        await observer.poll(sourceInstance: "process-one")
        #expect(await observer.activity().isEmpty)
        try fixture.append(file, [resultLine("unanchored")])
        await observer.poll(sourceInstance: "process-one")
        #expect(await observer.activity().isEmpty)
        try fixture.append(file, [initLine("live"), resultLine("live-result")])
        await observer.poll(sourceInstance: "process-one")
        #expect(await observer.activity().first?.status == .completed)
        #expect(await observer.activity().first?.turnID == "live")
    }

    @Test func newFilesAndIndependentAccountsKeepDistinctActivity() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer()
        await observer.poll(sourceInstance: "p")
        let first = try fixture.session(account: "first"), second = try fixture.session(account: "second")
        try fixture.append(first, [initLine(), resultLine()])
        try fixture.append(second, [initLine()])
        await observer.poll(sourceInstance: "p")
        let views = await observer.activity()
        #expect(views.count == 2)
        #expect(Set(views.map(\.id)).count == 2)
        #expect(views.filter { $0.status == .completed }.count == 1)
        #expect(views.filter { $0.status == .running }.count == 1)
    }

    @Test func partialRecordsCannotProduceCompletion() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer()
        let file = try fixture.session()
        await observer.poll(sourceInstance: "p")
        try fixture.append(file, [initLine()])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .running)
        let result = try resultLine(), half = result.count / 2
        try fixture.append(file, [Data(result.prefix(half))], newline: false)
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [Data(result.dropFirst(half))])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .completed)
    }

    @Test func sourceLossStopAndRestartRequireFreshNativeInit() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer(), file = try fixture.session()
        await observer.poll(sourceInstance: "first")
        try fixture.append(file, [initLine()]); await observer.poll(sourceInstance: "first")
        #expect(await observer.activity().first?.status == .running)
        await observer.poll(sourceInstance: nil)
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [resultLine()])
        await observer.poll(sourceInstance: "second")
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [initLine("new"), resultLine("new-result")])
        await observer.poll(sourceInstance: "second")
        #expect(await observer.activity().first?.status == .completed)
        await observer.stop()
        #expect(await observer.activity().first?.status == .unknown)
    }

    @Test(arguments: ["rotate", "truncate", "rewrite"]) func changedFileCannotReplayTerminalHistory(change: String) async throws {
        let fixture = try AuditFixture(), observer = fixture.observer(), file = try fixture.session()
        await observer.poll(sourceInstance: "p")
        try fixture.append(file, [initLine("init-A")]); await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .running)
        if change == "rotate" { try FileManager.default.removeItem(at: file); try Data().write(to: file) }
        if change == "truncate" { try Data().write(to: file) }
        if change == "rewrite" {
            var replacement = try initLine("init-B"); replacement.append(10); try replacement.write(to: file)
        }
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [resultLine("unanchored")]); await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [initLine("fresh"), resultLine("fresh-result")]); await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .completed)
    }

    @Test func symlinksAreRejectedAndArchivedMetadataRemovesCurrentActivity() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer(), file = try fixture.session()
        await observer.poll(sourceInstance: "p")
        try fixture.append(file, [initLine()]); await observer.poll(sourceInstance: "p")
        let external = fixture.root.appendingPathComponent("outside.jsonl")
        try fixture.append(file, [resultLine()]); try Data(contentsOf: file).write(to: external)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: external)
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .unknown)
        try FileManager.default.removeItem(at: file); try Data().write(to: file)
        try fixture.append(file, [initLine("recover")]); await observer.poll(sourceInstance: "p")
        let metadata = file.deletingLastPathComponent().appendingPathExtension("json")
        try JSONSerialization.data(withJSONObject: ["sessionId": "local_one", "isArchived": true]).write(to: metadata)
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().isEmpty)
    }

    @Test func oversizeAndMalformedRecordsInvalidateUntilNewInit() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer(), file = try fixture.session()
        await observer.poll(sourceInstance: "p")
        try fixture.append(file, [initLine()]); await observer.poll(sourceInstance: "p")
        try fixture.append(file, [Data(repeating: 120, count: 600_000), resultLine()])
        for _ in 0..<4 { await observer.poll(sourceInstance: "p") }
        #expect(await observer.activity().first?.status == .unknown)
        try fixture.append(file, [Data("{broken".utf8), initLine("fresh"), resultLine("fresh-result")])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .completed)
    }

    @Test func oldFileFirstDiscoveredAfterStartIsNotReplayed() async throws {
        let fixture = try AuditFixture()
        let observer = ClaudeDesktopObserver(root: fixture.root, now: { Date(timeIntervalSince1970: 4_102_444_800) })
        await observer.poll(sourceInstance: "p")
        let file = try fixture.session()
        try fixture.append(file, [initLine(), resultLine()])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().isEmpty)
        try fixture.append(file, [initLine("live"), resultLine("live-result")])
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().first?.status == .completed)
    }

    @Test func sessionCapacityIsExplicitAndDoesNotGrowPresentationWithoutBound() async throws {
        let fixture = try AuditFixture(), observer = fixture.observer()
        await observer.poll(sourceInstance: "p")
        for index in 0..<17 {
            let file = try fixture.session("local_\(index)")
            try fixture.append(file, [initLine("turn-\(index)")])
        }
        await observer.poll(sourceInstance: "p")
        #expect(await observer.activity().count == 16)
        #expect(await observer.health().contains("capacity exceeded"))
    }
}
