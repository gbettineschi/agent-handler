import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

struct DesktopHealthTests {
    @Test func rapidlyReplacingAnEmptySelectionDoesNotLeaveAHealthyStreamStopped() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let stream = DesktopStream(dataDirectory: server.directory); defer { stream.stop() }
        stream.follow(["thread"])
        try await eventually { stream.thread("thread") != nil }
        stream.follow([])
        #expect(stream.diagnosticState.connection == .stopped)
        stream.follow(["thread"])
        try await eventually { stream.thread("thread") != nil && stream.diagnosticState.connection == .connected }
        #expect(server.answers.isEmpty)
    }

    @Test func missingSocketExplainsConnectionFailure() async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/ah-missing-\(UUID().uuidString)")
        let adapter = DesktopAdapter(directory: directory, controller: RequestController(ledger: MemoryLedger()))
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().message.contains("Can't connect to Codex") }
        #expect(await adapter.health().known == 0)
        #expect(await adapter.health().diagnostics.connection == .unavailable)
        await adapter.stop()
    }

    @Test func ownerlessChatIsNotReportedAsAProtocolFailure() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        server.owner = nil
        let adapter = DesktopAdapter(directory: server.directory, controller: RequestController(ledger: MemoryLedger()))
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().message.contains("No open Codex conversation") }
        #expect(await adapter.health().known == 0)
        #expect(await adapter.health().diagnostics.connection == .connected)
        #expect(await adapter.health().diagnostics.issues[.ownerUnavailable] == 1)
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }

    @Test func changedProtocolExplainsWhyAnswersAreUnavailable() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState()), streamVersion: 12); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().message.contains("Unsupported Codex stream version") }
        #expect(await core.snapshot().isEmpty)
        #expect(await adapter.health().diagnostics.issues[.unsupportedVersion] == 1)
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }

    @Test func unreadableStateKeepsTheOwnerAndExplainsTheFailure() async throws {
        let unknown = try JSONValue.parse(fixtureState(extraItems: [["type": "futureTool", "id": "secret-item"]]))
        let server = try FixtureDesktopServer(state: unknown); defer { server.stop() }
        let adapter = DesktopAdapter(directory: server.directory, controller: RequestController(ledger: MemoryLedger()))
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().message.contains("Conversation data isn't supported") }
        #expect(await adapter.health().observedConversations == ["thread"])
        #expect(await adapter.health().message.contains("secret-item") == false)
        server.state = try JSONValue.parse(fixtureState(questions: []))
        try await eventually { await adapter.health().diagnostics.issues[.questionsUnsupported] == nil }
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }

    @Test func revisionGapShowsRecoveryUntilFreshStateArrives() async throws {
        let state = try JSONValue.parse(fixtureState())
        let server = try FixtureDesktopServer(state: state); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().count == 2 }
        server.change([], base: 999)
        try await eventually { await core.snapshot().allSatisfy { $0.state == .unavailable } }
        #expect(await adapter.health().message.contains("Refreshing Codex state"))
        #expect(await adapter.health().diagnostics.issues[.resynchronizing] == 1)
        server.state = state
        try await eventually { await core.snapshot().allSatisfy { $0.state == .pending } }
        #expect(await adapter.health().message.contains("Refreshing Codex state") == false)
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }

    @Test func retainedStateLimitHasItsOwnExplanation() async throws {
        let state = JSONValue.object(["retained": .array(Array(repeating: .string(String(repeating: "x", count: 2048)), count: 5000))])
        let server = try FixtureDesktopServer(state: state, fragmentSize: 65536); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().message.contains("Conversation exceeds the tracking limit") }
        #expect(await core.snapshot().isEmpty)
        #expect(await adapter.health().diagnostics.issues[.capacityExceeded] == 1)
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }

    @Test func refusedHandshakeDoesNotLeakTheNativeError() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState()), initializeError: "secret-reason"); defer { server.stop() }
        let adapter = DesktopAdapter(directory: server.directory, controller: RequestController(ledger: MemoryLedger()))
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.health().message.contains("Codex refused the companion connection") }
        #expect(await adapter.health().message.contains("secret-reason") == false)
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }

    @Test func disconnectAndRecoveryKeepRequestsWithoutReplayingAnswers() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        server.disconnectFollowers()
        try await eventually { await core.snapshot().filter { $0.state == .unavailable }.count == 2 }
        #expect(await adapter.health().diagnostics.connection == .unavailable)
        await adapter.stop()
        #expect(await adapter.health().diagnostics.connection == .stopped)
        #expect(await adapter.health().diagnostics.issues.isEmpty)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        #expect(await adapter.health().diagnostics.connection == .connected)
        #expect(await adapter.health().diagnostics.issues[.resynchronizing] == nil)
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }
}
