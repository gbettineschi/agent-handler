import Foundation
import Testing
@testable import AgentHandlerCore

actor GateTransport: ResponseTransport {
    var count = 0
    var reply: CheckedContinuation<DeliveryOutcome, Never>?
    var started: CheckedContinuation<Void, Never>?
    func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome {
        count += 1
        return await withCheckedContinuation { reply = $0; started?.resume(); started = nil }
    }
    func waitForStart() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while count == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(count > 0, "Controller must invoke the transport")
    }
    func finish(_ outcome: DeliveryOutcome = .accepted) { reply?.resume(returning: outcome); reply = nil }
}
struct ImmediateTransport: ResponseTransport {
    let outcome: DeliveryOutcome
    func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome { outcome }
}

struct ControllerTests {
    @Test func persistenceFailureKeepsFutureQuestionsDisabled() async throws {
        let ledger = FailsFirstStatusLedger(), core = RequestController(ledger: ledger)
        let epoch = await core.begin(scope: scope), q = question()
        await core.observe(observation([q], epoch: epoch))
        #expect(await core.persistenceFailed)
        await core.observe(observation([q], epoch: epoch, revision: 2))
        #expect(await core.snapshot().first?.state == .unavailable)
    }
    @Test func newEpochFencesOutstandingReceipt() async throws {
        let core = RequestController(ledger: MemoryLedger()), wire = GateTransport(), q = question()
        let epoch = await core.begin(scope: scope)
        await core.observe(observation([q], epoch: epoch))
        let sending = Task { try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .text("Yes"), using: wire) }
        try await wire.waitForStart()
        _ = await core.begin(scope: scope)
        await wire.finish()
        try await sending.value
        #expect(await core.snapshot().first?.state != .accepted)
    }
    @Test func doubleClickSendsOnlyOnce() async throws {
        let core = RequestController(ledger: MemoryLedger())
        let epoch = await core.begin(scope: scope), q = question()
        await core.observe(observation([q], epoch: epoch))
        let wire = GateTransport()
        let first = Task { try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .text("Yes"), using: wire) }
        try await wire.waitForStart()
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .text("Yes"), using: wire)
        }
        await wire.finish()
        try await first.value
        #expect(await wire.count == 1)
        #expect(await core.snapshot().first?.state == .accepted)
    }

    @Test func staleAndUnadvertisedResponsesAreRejected() async throws {
        let core = RequestController(ledger: MemoryLedger())
        let epoch = await core.begin(scope: scope), q = question()
        await core.observe(observation([q], epoch: epoch))
        for answer: UserAnswer in [.option("missing"), .decision("allow-all")] {
            await #expect(throws: ResponseError.self) {
                try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: answer, using: ImmediateTransport(outcome: .accepted))
            }
        }
        await core.observe(observation([question(title: "Changed")], epoch: epoch, revision: 2))
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .text("Yes"), using: ImmediateTransport(outcome: .accepted))
        }
    }

    @Test func lateReceiptDoesNotAcceptReplacement() async throws {
        let core = RequestController(ledger: MemoryLedger()), wire = GateTransport(), q = question()
        let epoch = await core.begin(scope: scope)
        await core.observe(observation([q], epoch: epoch))
        let sending = Task { try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .option("a"), using: wire) }
        try await wire.waitForStart()
        await core.observe(observation([question(title: "Replacement")], epoch: epoch, revision: 2))
        await wire.finish()
        try await sending.value
        #expect(await core.snapshot().first?.state == .uncertain)
    }

    @Test func uncertainCannotRetryAfterFreshSnapshot() async throws {
        let core = RequestController(ledger: MemoryLedger()), q = question()
        let epoch = await core.begin(scope: scope)
        await core.observe(observation([q], epoch: epoch))
        try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .text("Yes"), using: ImmediateTransport(outcome: .uncertain))
        await core.observe(observation([q], epoch: epoch, revision: 2))
        #expect(await core.snapshot().first?.state == .uncertain)
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: q.key, fingerprint: q.fingerprint, answer: .text("Yes"), using: ImmediateTransport(outcome: .accepted))
        }
    }

    @Test func approvalAllowsOnlyNativeChoices() async throws {
        let core = RequestController(ledger: MemoryLedger())
        let epoch = await core.begin(scope: scope)
        let request = AttentionRequest(key: question().key, owner: "owner", title: "Read file?",
            content: .approval(choices: [.init(id: "once", label: "Allow once"), .init(id: "deny", label: "Deny")]))
        await core.observe(observation([request], epoch: epoch))
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: request.key, fingerprint: request.fingerprint, answer: .decision("always"), using: ImmediateTransport(outcome: .accepted))
        }
        try await core.respond(key: request.key, fingerprint: request.fingerprint, answer: .decision("once"), using: ImmediateTransport(outcome: .accepted))
        #expect(await core.snapshot().first?.state == .accepted)
    }
}

private final class FailsFirstStatusLedger: DeliveryLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var first = true
    struct Failed: Error {}
    func status(for key: RequestKey) throws -> LedgerEntry? {
        try lock.withLock { if first { first = false; throw Failed() }; return nil }
    }
    func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws {}
    func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws {}
    func close(key: RequestKey) throws {}
}
