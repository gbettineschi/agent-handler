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
    @Test func nativeTitleFollowsOwnerSnapshotAndRenameWithoutSendingAnswers() async throws {
        var state = try #require(JSONValue.parse(fixtureState(questions: [])).objectValue)
        state["title"] = .string("Real chat title")
        let server = try FixtureDesktopServer(state: .object(state))
        defer { server.stop() }
        let adapter = DesktopAdapter(directory: server.directory, controller: RequestController(ledger: MemoryLedger()))
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.conversationTitles()["thread"] == "Real chat title" }
        server.change([.object(["op": .string("replace"), "path": .array([.string("title")]), "value": .string("Renamed chat")])])
        try await eventually { await adapter.conversationTitles()["thread"] == "Renamed chat" }
        #expect(server.answers.isEmpty)
        await adapter.start(threadIDs: [])
        #expect(await adapter.conversationTitles().isEmpty)
        await adapter.stop()
    }

    @Test func nativeActivityCompletionDisconnectStopAndUnfollow() async throws {
        let running = try JSONValue.parse(fixtureState(questions: []))
        let server = try FixtureDesktopServer(state: running)
        defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await adapter.activity().first?.status == .running }
        let completed = String(decoding: try fixtureState(questions: []), as: UTF8.self)
            .replacingOccurrences(of: "inProgress", with: "completed")
        server.state = try JSONValue.parse(Data(completed.utf8))
        try await eventually { await adapter.activity().first?.status == .completed }
        server.stop()
        try await eventually { await adapter.activity().first?.status == .unknown }
        await adapter.stop()
        #expect(await adapter.activity().first?.status == .unknown)
        await adapter.start(threadIDs: [])
        #expect(await adapter.activity().isEmpty)
        #expect(await core.snapshot().isEmpty)
    }
    @Test func replyTurnHydrationPreservesUnansweredSibling() async throws {
        let text = String(decoding: try fixtureState(), as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        let original = try JSONValue.parse(Data(text.utf8))["turns"].arrayValue![0]
        let server = try FixtureDesktopServer(state: .object(["turns": .array([original])]))
        defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        var replyTurn: [String: JSONValue] = ["turnId": .string("reply-turn"), "status": .string("inProgress"), "items": .array([])]
        server.state = .object(["turns": .array([original, .object(replyTurn)])])
        try await eventually { await core.snapshot().filter { $0.state == .unavailable }.count == 2 }
        let reply = #"<send_user_message_question_reply>[{"questionItemId":"[\"request_user_input_async\",\"message\",0]","question":"First?","answer":"Yes"}]</send_user_message_question_reply>"#
        replyTurn["items"] = .array([.object(["type": .string("userMessage"),
            "content": .array([.object(["type": .string("text"), "text": .string(reply)])])])])
        server.state = .object(["turns": .array([original, .object(replyTurn)])])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 1 }
        #expect(await core.snapshot().first { $0.state == .pending }?.request.title == "Second?")
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }
    @Test(arguments: [true, false]) func completedQuestionStartsReplyWithInheritedSettings(acknowledges: Bool) async throws {
        let text = String(decoding: try fixtureState(), as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        let server = try FixtureDesktopServer(state: JSONValue.parse(Data(text.utf8)), acknowledges: acknowledges)
        defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        let first = try #require(await core.snapshot().first { $0.request.title == "First?" })
        try await core.respond(key: first.id, fingerprint: first.request.fingerprint, answer: .option("0"), using: adapter)
        #expect(await core.snapshot().first { $0.id == first.id }?.state == (acknowledges ? .accepted : .uncertain))
        let sent = try #require(server.answers.first)
        #expect(sent["method"] == .string("thread-follower-start-turn"))
        #expect(sent["version"] == .integer(2))
        let start = sent["params"]["turnStart"]
        #expect(start["request"]["threadId"] == .string("thread"))
        #expect(start["request"]["turnTrigger"] == .string("send_user_message_async_question"))
        #expect(Set(start["request"].objectValue?.keys ?? [:].keys) == ["threadId", "input", "clientUserMessageId", "turnTrigger"])
        #expect(start["context"]["inheritThreadSettings"] == .bool(true))
        #expect(server.answers.count == 1)
        #expect(await core.snapshot().first { $0.request.title == "Second?" }?.state == .pending)
        await adapter.stop()
    }
    // Retaining unrelated tool output used to push ordinary long conversations over the state cap.
    @Test(arguments: [false, true]) func largeToolHistoryPreservesQuestionsAndPatches(canonical: Bool) async throws {
        let tools: [[String: Any]] = (0..<900).map { index in
            ["type": "commandExecution", "id": "tool-\(index)",
             "output": ["blocks": [["text": String(repeating: "x", count: 10_000)]]]]
        }
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState(canonical: canonical, extraItems: tools)), fragmentSize: 65_536)
        defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 2 }
        let prefix: [JSONValue] = canonical
            ? [.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string("turn-key"), .string("items")]
            : [.string("turns"), .integer(0), .string("items")]
        server.change([
            .object(["op": .string("replace"), "path": .array(prefix + [.integer(1), .string("output"), .string("blocks"), .integer(0), .string("text")]), "value": .string("Updated tool output")]),
            .object(["op": .string("replace"), "path": .array(prefix + [.integer(0), .string("questions"), .integer(0), .string("title")]), "value": .string("Updated first?")])
        ])
        try await eventually { await core.snapshot().contains { $0.request.title == "Updated first?" && $0.state == .pending } }
        let reply = #"<send_user_message_question_reply>[{"questionItemId":"[\"request_user_input_async\",\"message\",0]","question":"Updated first?","answer":"Yes"}]</send_user_message_question_reply>"#
        server.change([.object(["op": .string("add"), "path": .array(prefix + [.string("-")]), "value": .object([
            "type": .string("steeringUserMessage"), "status": .string("accepted"),
            "input": .array([.object(["type": .string("text"), "text": .string(reply)])])
        ])])])
        try await eventually { await core.snapshot().filter { $0.state == .pending }.count == 1 }
        #expect(await core.snapshot().first { $0.state == .pending }?.request.title == "Second?")
        #expect(server.follows == 1)
        await adapter.stop()
    }
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
        server.pauseDiscoveryResponses()
        let sending = Task { try await core.respond(key: request.id, fingerprint: request.request.fingerprint, answer: .text("Yes"), using: adapter) }
        try await eventually { server.methods.filter { $0 == "thread-owner-discovery" }.count > discovered }
        // The native preflight cannot complete until cancellation has been issued.
        #expect(server.answers.isEmpty)
        sending.cancel()
        server.resumeDiscoveryResponses()
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
