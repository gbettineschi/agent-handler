import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

private func reconnectApproval(_ kind: String, changed: Bool = false) throws -> JSONValue {
    var state = approvalState(extra: ["command": .string(changed ? "printf replacement" : "printf test")])
    if kind == "browser" {
        let origin = changed ? "https://example.org" : "https://example.com"
        let params: JSONValue = .object([
            "threadId": .string("thread"), "turnId": .string("turn"), "mode": .string("form"),
            "message": .string("Allow access to the fixture origin?"),
            "requestedSchema": .object(["type": .string("object"), "properties": .object([:])]),
            "_meta": .object(["codex_approval_kind": .string("mcp_tool_call"), "connector_id": .string("browser-use"),
                "tool_name": .string("access_browser_origin"), "tool_params": .object(["origin": .string(origin)]),
                "persist": .array([.string("session"), .string("always")])])
        ])
        try DesktopPatches.apply([.object(["op": .string("replace"), "path": .array([.string("requests")]),
            "value": .array([.object(["id": .string("fixture-browser"), "method": .string("mcpServer/elicitation/request"), "params": params])])])], to: &state)
    }
    return state
}

private func afterReconnect(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(8)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    try #require(await condition(), "Fixture reconnect did not recover within eight seconds")
}

struct DesktopApprovalReconnectTests {
    @Test(arguments: ["session", "deny"])
    func browserDecisionPreservesWireScopeAndNeedsAuthoritativeWithdrawal(decision: String) async throws {
        let server = try FixtureDesktopServer(state: reconnectApproval("browser")); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        let request = try #require(await core.snapshot().first { $0.state == .pending })
        #expect(request.request.title.contains("https://example.com"))
        try await core.respond(key: request.id, fingerprint: request.request.fingerprint, answer: .decision(decision), using: adapter)
        let sent = try #require(server.answers.first)
        #expect(sent["method"] == .string("thread-follower-submit-mcp-server-elicitation-response"))
        #expect(sent["targetClientId"] == .string("desktop-owner"))
        #expect(sent["params"]["requestId"] == .string("fixture-browser"))
        #expect(sent["params"]["conversationId"] == .string("thread"))
        let expected: JSONValue = decision == "session"
            ? .object(["action": .string("accept"), "content": .object([:]), "_meta": .object(["persist": .string("session")])])
            : .object(["action": .string("decline"), "content": .null, "_meta": .null])
        #expect(sent["params"]["response"] == expected)
        #expect(await core.snapshot().first?.state == .uncertain)
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: request.id, fingerprint: request.request.fingerprint, answer: .decision(decision), using: adapter)
        }
        #expect(server.answers.count == 1)
        server.state = .object(["requests": .array([]), "turns": .array([])])
        try await eventually { await core.snapshot().first?.state == .closed }
        await adapter.stop()
    }

    @Test(arguments: ["command", "browser"])
    func socketReconnectRejectsTheOldDisplayedApproval(kind: String) async throws {
        let server = try FixtureDesktopServer(state: reconnectApproval(kind)); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        let old = try #require(await core.snapshot().first)
        server.pauseDiscoveryResponses()
        server.disconnectFollowers()
        try await eventually { await core.snapshot().first?.state == .unavailable }
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: old.id, fingerprint: old.request.fingerprint,
                answer: .decision(kind == "browser" ? "session" : "accept"), using: adapter)
        }
        server.state = try reconnectApproval(kind, changed: true)
        server.resumeDiscoveryResponses()
        try await afterReconnect { await core.snapshot().contains { $0.state == .pending && $0.request.fingerprint != old.request.fingerprint } }
        let recovered = try #require(await core.snapshot().first { $0.state == .pending })
        #expect(recovered.id == old.id)
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: old.id, fingerprint: old.request.fingerprint,
                answer: .decision(kind == "browser" ? "session" : "accept"), using: adapter)
        }
        #expect(server.answers.isEmpty)
        try await core.respond(key: recovered.id, fingerprint: recovered.request.fingerprint,
            answer: .decision(kind == "browser" ? "session" : "accept"), using: adapter)
        #expect(server.answers.count == 1)
        #expect(await core.snapshot().first?.state == .uncertain)
        await adapter.stop()
    }

    @Test(arguments: ["command", "browser"], [false, true])
    func uncertainApprovalCannotResendAfterLedgerAndAdapterReopen(kind: String, dropReply: Bool) async throws {
        let server = try FixtureDesktopServer(state: reconnectApproval(kind), dropAnswer: dropReply); defer { server.stop() }
        let database = server.directory.appendingPathComponent("delivery/ledger.sqlite")
        let key: RequestKey, fingerprint: String
        do {
            let core = RequestController(ledger: try SQLiteLedger(url: database))
            let adapter = DesktopAdapter(directory: server.directory, controller: core)
            await adapter.start(threadIDs: ["thread"])
            try await eventually { await core.snapshot().contains { $0.state == .pending } }
            let request = try #require(await core.snapshot().first)
            key = request.id; fingerprint = request.request.fingerprint
            try await core.respond(key: key, fingerprint: fingerprint,
                answer: .decision(kind == "browser" ? "session" : "accept"), using: adapter)
            #expect(await core.snapshot().first?.state == .uncertain)
            await adapter.stop()
        }
        let reopened = try SQLiteLedger(url: database), core = RequestController(ledger: reopened)
        let adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().first?.state == .uncertain }
        #expect(try reopened.status(for: key)?.status == .uncertain)
        server.state = try reconnectApproval(kind, changed: true)
        try await eventually { await core.snapshot().contains { $0.state == .uncertain && $0.request.fingerprint != fingerprint } }
        let changed = try #require(await core.snapshot().first)
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: changed.id, fingerprint: changed.request.fingerprint,
                answer: .decision(kind == "browser" ? "session" : "accept"), using: adapter)
        }
        #expect(server.answers.count == 1)
        server.state = .object(["requests": .array([]), "turns": .array([])])
        try await eventually { await core.snapshot().first?.state == .closed }
        #expect(try reopened.status(for: key)?.status == .closed)
        await adapter.stop()
    }

    @Test(arguments: ["command", "browser"])
    func stoppingDuringApprovalPreflightDoesNotWriteADecision(kind: String) async throws {
        let server = try FixtureDesktopServer(state: reconnectApproval(kind)); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        let request = try #require(await core.snapshot().first)
        let discoveries = server.methods.filter { $0 == "thread-owner-discovery" }.count
        server.pauseDiscoveryResponses()
        let sending = Task {
            try await core.respond(key: request.id, fingerprint: request.request.fingerprint,
                answer: .decision(kind == "browser" ? "session" : "accept"), using: adapter)
        }
        try await eventually { server.methods.filter { $0 == "thread-owner-discovery" }.count > discoveries }
        await adapter.stop()
        server.resumeDiscoveryResponses()
        try await sending.value
        #expect(server.answers.isEmpty)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }
}
