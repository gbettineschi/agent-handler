import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

struct DesktopHealthTests {
    @Test func selectionApplicationProtectsANewSourceWaitRatherThanUsingOldClearActivity() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState(questions: []))); defer { server.stop() }
        let adapter = DesktopAdapter(directory: server.directory, controller: RequestController(ledger: MemoryLedger()))
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.activity().first?.status == .running }
        #expect(await adapter.health().sourceApprovalConversations.isEmpty)
        #expect(await adapter.activity().first?.attention == .clear)
        var fields = try #require(server.state.objectValue)
        fields["requests"] = .array([.object(["id": .integer(42), "method": .string("mcpServer/elicitation/request"),
            "params": .object(["threadId": .string("thread"), "turnId": .string("native-turn"),
                "_meta": .object(["codex_approval_kind": .string("mcp_tool_call"), "connector_id": .string("another-connector")])])])])
        server.state = .object(fields)
        try await eventually { await adapter.health().sourceApprovalConversations == ["thread"] }
        server.owner = nil
        server.disconnectFollowers()
        // Includes the real stream reconnect backoff, not just a local reduction.
        try await eventually(timeout: .seconds(6)) { await adapter.health().unownedConversations == ["thread"] }
        let selected = await adapter.start(selecting: { health, activities in
            #expect(health.unownedConversations == ["thread"])
            #expect(health.sourceApprovalConversations == ["thread"])
            #expect(health.observedConversations == ["thread"])
            #expect(activities.first?.status == .unknown)
            return health.sourceApprovalConversations.isEmpty ? ["new-chat"] : ["thread"]
        })
        #expect(selected == ["thread"])
        #expect(await adapter.health().sourceApprovalConversations == ["thread"])
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }
    @Test func confirmedOwnerAbsenceSurvivesSearchRetryAndClearsOnRecovery() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState(questions: []))); defer { server.stop() }
        server.owner = nil
        let stream = DesktopStream(dataDirectory: server.directory); defer { stream.stop() }
        stream.retry = 0.1
        stream.follow(["thread"])
        try await eventually { stream.diagnosticState.unowned == ["thread"] }
        server.pauseDiscoveryResponses()
        try await eventually { stream.diagnosticState.issues["thread"] == .awaitingOwner }
        #expect(stream.diagnosticState.unowned == ["thread"])
        server.owner = "recovered-owner"
        server.resumeDiscoveryResponses()
        try await eventually { stream.thread("thread")?.ownerClientID == "recovered-owner" }
        #expect(stream.diagnosticState.unowned.isEmpty)
        #expect(server.answers.isEmpty)
    }

    @Test func ownerAbsenceIsScopedToTheCurrentSelectionAndConnection() async throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState(questions: []))); defer { server.stop() }
        server.owner = nil
        let stream = DesktopStream(dataDirectory: server.directory); defer { stream.stop() }
        stream.retry = 0.1
        stream.follow(["thread"])
        try await eventually { stream.diagnosticState.unowned == ["thread"] }
        stream.follow([])
        #expect(stream.diagnosticState.unowned.isEmpty)
        stream.follow(["thread"])
        try await eventually { stream.diagnosticState.unowned == ["thread"] }
        server.stop()
        try await eventually { stream.diagnosticState.connection != .connected && stream.diagnosticState.unowned.isEmpty }
        stream.stop()
        #expect(stream.diagnosticState.unowned.isEmpty)
        #expect(server.answers.isEmpty)
    }
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
        #expect(await adapter.health().unownedConversations == ["thread"])
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
        #expect(await adapter.health().unownedConversations.isEmpty)
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
