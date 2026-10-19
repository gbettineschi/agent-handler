import Foundation
import Testing
@testable import AgentHandlerCore

private final class ReadFaultLedger: DeliveryLedger, @unchecked Sendable {
    private let lock = NSLock()
    let base: SQLiteLedger
    private var fail = false
    enum Fault: Error { case read }
    init(_ base: SQLiteLedger) { self.base = base }
    func failReads() { lock.withLock { fail = true } }
    func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws { try base.reserve(key: key, fingerprint: fingerprint, attemptID: attemptID) }
    func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws { try base.finish(key: key, attemptID: attemptID, outcome: outcome) }
    func status(for key: RequestKey) throws -> LedgerEntry? {
        if lock.withLock({ fail }) { throw Fault.read }
        return try base.status(for: key)
    }
    func close(key: RequestKey) throws { try base.close(key: key) }
}

struct RecoverySafetyTests {
    @Test(arguments: [false, true], [DeliveryOutcome.notSent, .rejected, .uncertain])
    func sqliteRecoveryWithOwnerChange(firstSnapshot: Bool, outcome: DeliveryOutcome) async throws {
        let url = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SQLiteLedger(url: url), core = RequestController(ledger: ledger), gate = GateTransport()
        let old = question()
        let new = AttentionRequest(key: old.key, owner: "new-owner", title: old.title, content: old.content)
        #expect(new.fingerprint != old.fingerprint)
        let epoch = await core.begin(scope: scope)
        await core.observe(observation([old], epoch: epoch))
        let send = Task { try await core.respond(key: old.key, fingerprint: old.fingerprint, answer: .text("old"), using: gate) }
        try await gate.waitForStart()
        let recovered = await core.begin(scope: scope)
        if firstSnapshot { await core.observe(observation([new], epoch: recovered)) }
        await gate.finish(outcome); try await send.value
        if !firstSnapshot { await core.observe(observation([new], epoch: recovered)) }
        #expect(await core.snapshot().first?.state == (outcome == .uncertain ? .uncertain : .pending))
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: old.key, fingerprint: old.fingerprint, answer: .text("stale"), using: gate)
        }
        #expect(await gate.count == 1)
    }

    @Test(arguments: [DeliveryOutcome.notSent, .rejected])
    func closedReplacementExistsBeforeLateResult(outcome: DeliveryOutcome) async throws {
        let url = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SQLiteLedger(url: url), core = RequestController(ledger: ledger), gate = GateTransport()
        let old = question(), new = question(title: "replacement")
        let epoch = await core.begin(scope: scope)
        await core.observe(observation([old], epoch: epoch))
        let send = Task { try await core.respond(key: old.key, fingerprint: old.fingerprint, answer: .text("old"), using: gate) }
        try await gate.waitForStart()
        await core.observe(observation([], epoch: epoch, revision: 2))
        let recovered = await core.begin(scope: scope)
        await core.observe(observation([new], epoch: recovered))
        #expect(await core.snapshot().first?.state == .uncertain)
        await gate.finish(outcome); try await send.value
        #expect(try ledger.status(for: old.key)?.status == .closed)
        #expect(await core.snapshot().first?.state == .uncertain)
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: new.key, fingerprint: new.fingerprint, answer: .text("new"), using: gate)
        }
        #expect(await gate.count == 1)
    }

    @Test(arguments: [false, true])
    func statusReadFailureCannotUnlock(firstSnapshot: Bool) async throws {
        let url = try temporaryDatabase()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = ReadFaultLedger(try SQLiteLedger(url: url)), core = RequestController(ledger: ledger), gate = GateTransport()
        let old = question(), new = question(title: "replacement")
        let epoch = await core.begin(scope: scope)
        await core.observe(observation([old], epoch: epoch))
        let send = Task { try await core.respond(key: old.key, fingerprint: old.fingerprint, answer: .text("old"), using: gate) }
        try await gate.waitForStart()
        let recovered = await core.begin(scope: scope)
        if firstSnapshot { await core.observe(observation([new], epoch: recovered)) }
        ledger.failReads()
        await gate.finish(.notSent); try await send.value
        if !firstSnapshot { await core.observe(observation([new], epoch: recovered)) }
        #expect(await core.persistenceFailed)
        #expect(await core.snapshot().first?.state != .pending)
        await #expect(throws: ResponseError.persistenceUnavailable) {
            try await core.respond(key: new.key, fingerprint: new.fingerprint, answer: .text("new"), using: gate)
        }
        #expect(await gate.count == 1)
    }
}
