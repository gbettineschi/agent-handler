import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let end = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < end {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(await condition(), "Fixture condition did not arrive within three seconds")
}

struct DesktopAdapterTests {
    @Test func malformedQuestionStateRetainsCardsUntilValidRecovery() async throws {
        let valid = try JSONValue.parse(fixtureState())
        let server = try FixtureDesktopServer(state: valid); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        server.state = .object(["turns": .array([.object([:])])])
        try await eventually { await core.snapshot().allSatisfy { $0.state == .unavailable } }
        #expect(await core.snapshot().count == 2)
        server.state = valid
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        await adapter.stop()
    }
    @Test func gapRejectsSnapshotsBelowLatestObservedRevision() async throws {
        let empty = JSONValue.object(["turns": .array([])])
        let server = try FixtureDesktopServer(state: empty); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().known == 1 }
        server.change([], base: 0) // Observed revision 2; missing base must invalidate revision 1.
        try await eventually { await adapter.health().known == 0 }
        let obsolete = try JSONValue.parse(fixtureState())
        server.emitSnapshot(obsolete, thread: "thread", revision: 0)
        try await Task.sleep(for: .milliseconds(350))
        #expect(await core.snapshot().filter(\.needsAttention).isEmpty)
        server.emitSnapshot(obsolete, thread: "thread", revision: 1)
        try await Task.sleep(for: .milliseconds(350))
        #expect(await core.snapshot().filter(\.needsAttention).isEmpty)
        #expect(server.answers.isEmpty)
        server.emitSnapshot(empty, thread: "thread", revision: 2)
        try await eventually { await adapter.health().known == 1 }
        #expect(await core.snapshot().filter(\.needsAttention).isEmpty)
        await adapter.stop()
    }
    @Test func malformedSnapshotDoesNotDisableHealthyConversation() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["broken", "healthy"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 4 }
        server.emitSnapshot(.null, thread: "broken", revision: 2)
        try await eventually { await core.snapshot().filter { $0.id.scope.conversation == "broken" }.allSatisfy { $0.state == .unavailable } }
        #expect(await core.snapshot().filter { $0.id.scope.conversation == "healthy" && $0.state == .pending }.count == 2)
        await adapter.stop()
    }
    @Test func cancellationBeforeAnswerWriteDoesNotSend() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().count == 2 }
        let request = try #require(await core.snapshot().first)
        let discovered = server.methods.filter { $0 == "thread-owner-discovery" }.count
        server.discoveryDelay = 0.2
        let sending = Task { try await core.respond(key: request.id, fingerprint: request.request.fingerprint, answer: .text("Yes"), using: adapter) }
        try await eventually { server.methods.filter { $0 == "thread-owner-discovery" }.count > discovered }
        sending.cancel()
        try await sending.value
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }
    @Test func nativeQuestionRoundTripAndExternalResolution() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        let first = try #require(await core.snapshot().first { $0.request.title == "First?" })
        try await core.respond(key: first.id, fingerprint: first.request.fingerprint, answer: .option("0"), using: adapter)
        #expect(await core.snapshot().first { $0.id == first.id }?.state == .accepted)
        #expect(server.answers.count == 1)
        #expect(server.answers.first?["params"]["conversationId"].stringValue == "thread")
        server.state = .object(["requests": .array([]), "turns": .array([])])
        try await eventually { await core.snapshot().filter(\.needsAttention).isEmpty }
        await adapter.stop()
    }
    @Test(arguments: [true, false]) func mismatchOrLostReceiptIsUncertain(drop: Bool) async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState()), acknowledges: false, dropAnswer: drop)
        defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        let first = try #require(await core.snapshot().first)
        try await core.respond(key: first.id, fingerprint: first.request.fingerprint, answer: .text("User answer"), using: adapter)
        #expect(await core.snapshot().first { $0.id == first.id }?.state == .uncertain)
        #expect(server.answers.count == 1)
        await adapter.stop()
    }
    @Test func ownerTransferPreventsSending() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        let first = try #require(await core.snapshot().first)
        server.owner = "different-owner"
        try await core.respond(key: first.id, fingerprint: first.request.fingerprint, answer: .text("User answer"), using: adapter)
        #expect(server.answers.isEmpty)
        #expect(await core.snapshot().first { $0.id == first.id }?.state == .unavailable)
        await adapter.stop()
    }
    @Test func revisionGapDisablesAnswersWithoutClearingCards() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().count == 2 }
        server.change([], base: 999)
        try await eventually { await core.snapshot().allSatisfy { $0.state == .unavailable } }
        #expect(await core.snapshot().count == 2)
        await adapter.stop()
    }
}
