import Foundation
import Testing
import Darwin
@testable import CodexDesktopAdapter

struct CodexUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func payload(_ body: String) -> Data { Data(body.utf8) }

    @Test func currentBucketWinsAndShowsRemainingRatherThanConsumed() throws {
        let usage = try CodexUsageSnapshot.decode(payload(#"{"rateLimits":{"primary":{"usedPercent":10}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":29,"windowDurationMins":10080,"resetsAt":1800500000},"secondary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1800010000}}}}"#), fetchedAt: now)
        #expect(usage.windows.count == 2)
        #expect(usage.displayWindow(at: now)?.remainingPercent == 71)
        #expect(usage.displayWindow(at: now)?.durationMinutes == 10080)
    }

    @Test func legacyFallbackClampsAndMissingDataIsNeverFullQuota() throws {
        let usage = try CodexUsageSnapshot.decode(payload(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":110},"secondary":{"usedPercent":-2}}}"#), fetchedAt: now)
        #expect(usage.windows.map(\.remainingPercent) == [0, 100])
        for source in [#"{}"#, #"{"rateLimits":null}"#, #"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":0}}}}"#,
                       #"{"rateLimits":{"limitId":"other","primary":{"usedPercent":0}}}"#] {
            let empty = try CodexUsageSnapshot.decode(payload(source), fetchedAt: now)
            #expect(empty.displayWindow(at: now) == nil)
        }
    }

    @Test func expiredOrStaleSnapshotCannotClaimCurrentRemainingQuota() throws {
        let usage = try CodexUsageSnapshot.decode(payload(#"{"rateLimits":{"primary":{"usedPercent":99,"resetsAt":1800000060}}}"#), fetchedAt: now)
        #expect(usage.displayWindow(at: now)?.remainingPercent == 1)
        #expect(usage.displayWindow(at: now.addingTimeInterval(60)) == nil)
        let unknownReset = try CodexUsageSnapshot.decode(payload(#"{"rateLimits":{"primary":{"usedPercent":29}}}"#), fetchedAt: now)
        #expect(unknownReset.displayWindow(at: now.addingTimeInterval(181)) == nil)
        #expect(unknownReset.displayWindow(at: now.addingTimeInterval(-1)) == nil)
        let invalidReset = try CodexUsageSnapshot.decode(payload(#"{"rateLimits":{"primary":{"usedPercent":29,"resetsAt":1e30}}}"#), fetchedAt: now)
        #expect(invalidReset.displayWindow(at: now)?.resetsAt == nil)
    }

    @Test func readerOnlyInitializesAndReadsQuotaThenStopsItsChild() async throws {
        let fixture = try UsageEngineFixture(body: #"""
        import sys,json,os
        open('child-pid','w').write(str(os.getpid()))
        for line in sys.stdin:
            request=json.loads(line)
            with open('methods','a') as log: log.write(request['method']+'\n')
            if request['method']=='initialize':
                print(json.dumps({'id':0,'result':{}}),flush=True)
            if request['method']=='account/rateLimits/read':
                print(json.dumps({'id':1,'result':{'rateLimits':{'primary':{'usedPercent':29}}}}),flush=True)
        """#)
        defer { fixture.remove() }
        let usage = try await CodexUsageReader.read(executable: fixture.engine, directory: fixture.directory)
        #expect(usage.displayWindow(at: Date())?.remainingPercent == 71)
        let methods = try String(contentsOf: fixture.directory.appendingPathComponent("methods"), encoding: .utf8)
        #expect(methods == "initialize\ninitialized\naccount/rateLimits/read\n")
        #expect(try fixture.childStopped())
    }

    @Test(arguments: ["hang", "oversize", "cancel"]) func readerFailureIsBoundedAndCleansUp(mode: String) async throws {
        let fixture = try UsageEngineFixture(body: """
        import sys,os,time
        open('child-pid','w').write(str(os.getpid()))
        if '\(mode)'=='oversize':
            print('x'*1100000,flush=True)
        time.sleep(30)
        """)
        defer { fixture.remove() }
        let task = Task { try await CodexUsageReader.read(executable: fixture.engine, directory: fixture.directory, timeout: mode == "cancel" ? 10 : 1.5) }
        if mode == "cancel" {
            for _ in 0..<60 {
                if FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("child-pid").path) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            task.cancel()
        }
        let start = Date()
        do { _ = try await task.value; Issue.record("Expected a bounded reader failure") }
        catch { }
        #expect(Date().timeIntervalSince(start) < 4)
        #expect(try fixture.childStopped())
    }

    @Test(arguments: ["null", "eof", "malformed"]) func unsupportedRepliesDoNotEscapeTheReader(mode: String) async throws {
        let fixture = try UsageEngineFixture(body: """
        import sys,json,os
        open('child-pid','w').write(str(os.getpid()))
        sys.stdin.readline()
        if '\(mode)'=='null': print('{"id":0,"result":null}',flush=True)
        if '\(mode)'=='malformed': print('not-json',flush=True)
        """)
        defer { fixture.remove() }
        do { _ = try await CodexUsageReader.read(executable: fixture.engine, directory: fixture.directory); Issue.record("Expected unavailable quota") }
        catch { }
        #expect(try fixture.childStopped())
    }

    @Test func missingEngineReportsUnavailableWithoutWaitingForAnUnstartedChild() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { _ = try await CodexUsageReader.read(executable: missing, directory: .temporaryDirectory); Issue.record("Expected unavailable engine") }
        catch { }
    }
}

private struct UsageEngineFixture {
    let directory: URL
    let engine: URL
    init(body: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        engine = directory.appendingPathComponent("engine")
        try ("#!/usr/bin/python3\n" + body).write(to: engine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func childStopped() throws -> Bool {
        let pid = try String(contentsOf: directory.appendingPathComponent("child-pid"), encoding: .utf8)
        return kill(Int32(pid)!, 0) == -1 && errno == ESRCH
    }
}
