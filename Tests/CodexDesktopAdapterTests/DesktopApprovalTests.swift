import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

func approvalState(id: JSONValue = .integer(7), reviewer: String = "user", extra: [String: JSONValue] = [:]) -> JSONValue {
    var params: [String: JSONValue] = ["threadId": .string("thread"), "turnId": .string("turn"), "itemId": .string("command"),
        "command": .string("printf test"), "cwd": .string("/tmp"), "reason": .string("Harmless approval test"),
        "availableDecisions": .array([.string("accept"), .string("decline")])]
    params.merge(extra) { _, value in value }
    return .object(["requests": .array([.object(["id": id, "method": .string("item/commandExecution/requestApproval"), "params": .object(params)])]),
        "turns": .array([.object(["turnId": .string("turn"), "status": .string("inProgress"), "items": .array([]),
            "params": .object(["approvalsReviewer": .string(reviewer), "approvalPolicy": .string("on-request"),
                "sandboxPolicy": .object(["type": .string("workspaceWrite"), "writableRoots": .array([.string("/tmp")]), "networkAccess": .bool(false)])])])])])
}
func approvals(_ state: JSONValue) throws -> [DesktopApprovals.Pending] {
    try DesktopApprovals.pending(state: state, threadID: "thread", owner: "desktop-owner", installation: "fixture")
}
struct DesktopApprovalTests {
    @Test func presentationUsesNativeFieldsRatherThanSplittingPromptText() throws {
        let command = "printf 'line one\n\nDirectory: not a folder'"
        let pending = try #require(approvals(approvalState(extra: ["command": .string(command)])).first)
        #expect(pending.request.approvalDetails?.subject == .command(command: command, directory: "/tmp", reason: "Harmless approval test"))
    }
    @Test(arguments: [false, true], [false, true]) func nativeApprovalDispatchIsNotAnExecutionReceipt(dropReply: Bool, acknowledges: Bool) async throws {
        let server = try FixtureDesktopServer(state: approvalState(), acknowledges: acknowledges, dropAnswer: dropReply); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { if case .approval = $0.request.content { return $0.state == .pending }; return false } }
        let view = try #require(await core.snapshot().first { if case .approval = $0.request.content { return true }; return false })
        try await core.respond(key: view.id, fingerprint: view.request.fingerprint, answer: .decision("accept"), using: adapter)
        let sent = try #require(server.answers.first)
        #expect(sent["method"] == .string("thread-follower-command-approval-decision"))
        #expect(sent["params"]["requestId"] == .integer(7))
        #expect(sent["params"]["decision"] == .string("accept"))
        #expect(await core.snapshot().first { $0.id == view.id }?.state == .uncertain)
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: view.id, fingerprint: view.request.fingerprint, answer: .decision("accept"), using: adapter)
        }
        server.state = .object(["requests": .array([]), "turns": .array([])])
        try await eventually { await core.snapshot().filter(\.needsAttention).isEmpty }
        #expect(server.answers.count == 1)
        await adapter.stop()
    }
    @Test func commandIdentityAndExactChoices() throws {
        let one = try #require(approvals(approvalState()).first)
        let two = try #require(approvals(approvalState(id: .string("7"))).first)
        #expect(one.request.key.nativeID == .integer(7))
        #expect(two.request.key.nativeID == .string("7"))
        #expect(one.request.key != two.request.key)
        #expect(one.request.title.contains("printf test"))
        #expect(one.request.title.contains("/tmp"))
        #expect(one.responses["accept"] == .string("accept"))
        #expect(one.responses["acceptForSession"] == nil)
        #expect(one.method == "thread-follower-command-approval-decision")
    }
    @Test func automaticReviewAndUnknownRequiredDataDisableApproval() throws {
        #expect(throws: (any Error).self) { _ = try approvals(approvalState(reviewer: "auto_review")) }
        for extra: [String: JSONValue] in [
            ["command": .omitted], ["command": .string(String(repeating: "x", count: 17000))],
            ["availableDecisions": .array([.string("newDecision")])],
            ["networkApprovalContext": .object(["host": .string("example.com")])],
            ["additionalPermissions": .object(["network": .bool(true)])]
        ] { #expect(throws: (any Error).self) { _ = try approvals(approvalState(extra: extra)) } }
    }
    @Test func nativeCommandRuleChoicePreservesExactPayloadAndScope() throws {
        let rule = JSONValue.object(["acceptWithExecpolicyAmendment": .object([
            "execpolicy_amendment": .array([.string("/usr/bin/printf"), .string("test\\n")])])])
        let state = approvalState(extra: ["availableDecisions": .array([.string("accept"), rule, .string("cancel")])])
        let pending = try #require(approvals(state).first)
        #expect(pending.responses["accept"] == .string("accept"))
        #expect(pending.responses["cancel"] == .string("cancel"))
        #expect(pending.responses["command-rule-1"] == rule)
        guard case .approval(let choices) = pending.request.content else { Issue.record("Expected approval"); return }
        #expect(choices[1].label.contains("save command rule"))
        #expect(choices[1].label.contains("/usr/bin/printf"))
        #expect(pending.request.approvalDetails?.persistentActions["command-rule-1"] == .commandRule(prefix: ["/usr/bin/printf", "test\\n"]))
        let unknown = JSONValue.object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": .array([.string("printf")]), "future": .bool(true)])])
        #expect(throws: (any Error).self) { _ = try approvals(approvalState(extra: ["availableDecisions": .array([unknown])])) }
    }
    @Test func nativePayloadChangesInvalidateDisplayedFingerprint() throws {
        let first = try #require(approvals(approvalState()).first)
        let changed = try #require(approvals(approvalState(extra: ["approvalId": .string("different-native-target")])).first)
        #expect(first.request.key == changed.request.key)
        #expect(first.request.fingerprint != changed.request.fingerprint)
    }
    @Test func projectionPreservesReviewPolicyWithoutKeepingOtherTurnMetadata() throws {
        var state = approvalState()
        DesktopProjection.compact(&state)
        #expect(try approvals(state).count == 1)
    }
    @Test func incompleteOrUnknownEffectivePermissionsDisableApproval() throws {
        for (field, value): (String, JSONValue) in [
            ("approvalPolicy", .omitted), ("approvalPolicy", .null), ("approvalPolicy", .string("future-policy")),
            ("sandboxPolicy", .object(["type": .omitted])), ("sandboxPolicy", .null),
            ("sandboxPolicy", .object(["type": .string("future-sandbox")])),
            ("sandboxPolicy", .object(["type": .string("workspaceWrite"), "writableRoots": .omitted]))
        ] {
            var state = approvalState()
            try DesktopPatches.apply([.object(["op": .string("replace"),
                "path": .array([.string("turns"), .integer(0), .string("params"), .string(field)]), "value": value])], to: &state)
            #expect(throws: (any Error).self) { _ = try approvals(state) }
        }
        var state = approvalState()
        try DesktopPatches.apply([.object(["op": .string("add"),
            "path": .array([.string("turns"), .integer(0), .string("params"), .string("unrelated")]), "value": .string("ignored")])], to: &state)
        DesktopProjection.compact(&state)
        #expect(try approvals(state).first?.request.fingerprint == approvals(approvalState()).first?.request.fingerprint)
    }
    @Test func completedRequestWithdrawsButMalformedRequestDoesNot() throws {
        var state = approvalState()
        try DesktopPatches.apply([.object(["op": .string("add"), "path": .array([.string("requests"), .integer(0), .string("completed")]), "value": .bool(true)])], to: &state)
        #expect(try approvals(state).isEmpty)
        #expect(throws: (any Error).self) { _ = try approvals(.object(["requests": .array([.object([:])])])) }
    }
}

extension DesktopApprovalTests {
    @Test func granularPolicyAllowsOnlyItsEnabledPromptCategories() throws {
        // Native Desktop's granular preset permits MCP but forbids shell/rule prompts.
        let flags: [String: JSONValue] = ["sandbox_approval": .bool(false), "rules": .bool(false),
            "skill_approval": .bool(false), "request_permissions": .bool(true), "mcp_elicitations": .bool(true)]
        var state = approvalState()
        try DesktopPatches.apply([.object(["op": .string("replace"),
            "path": .array([.string("turns"), .integer(0), .string("params"), .string("approvalPolicy")]),
            "value": .object(["granular": .object(flags)])])], to: &state)
        #expect(throws: (any Error).self) { _ = try approvals(state) }
        let nativeMcp: JSONValue = .object(["id": .integer(42), "method": .string("mcpServer/elicitation/request"),
            "params": .object(["threadId": .string("thread"), "turnId": .string("turn"), "mode": .string("form"),
                "message": .string("Allow opening the harmless test app?"),
                "requestedSchema": .object(["type": .string("object"), "properties": .object([:])]),
                "_meta": .object(["codex_approval_kind": .string("mcp_tool_call"), "connector_id": .string("computer-use"),
                    "tool_name": .string("get_app_state"), "persist": .array([.string("session")]),
                    "tool_params": .object(["app": .string("com.example.Test")])])])])
        try DesktopPatches.apply([.object(["op": .string("replace"), "path": .array([.string("requests")]),
            "value": .array([nativeMcp])])], to: &state)
        let pending = try #require(approvals(state).first)
        #expect(pending.wireID == .integer(42))
        #expect(pending.responses["session"] == .object(["action": .string("accept"), "content": .object([:]),
            "_meta": .object(["persist": .string("session")])]))
        var changedSettings = state
        try DesktopPatches.apply([.object(["op": .string("replace"),
            "path": .array([.string("turns"), .integer(0), .string("params"), .string("approvalPolicy"), .string("granular"), .string("request_permissions")]),
            "value": .bool(false)])], to: &changedSettings)
        #expect(try approvals(changedSettings).first?.request.fingerprint != pending.request.fingerprint)
        for value: JSONValue in [.bool(false), .null, .string("true")] {
            var changed = state
            try DesktopPatches.apply([.object(["op": .string("replace"),
                "path": .array([.string("turns"), .integer(0), .string("params"), .string("approvalPolicy"), .string("granular"), .string("mcp_elicitations")]),
                "value": value])], to: &changed)
            #expect(throws: (any Error).self) { _ = try approvals(changed) }
        }
        for changedFlags in [flags.filter { $0.key != "rules" }, flags.merging(["future_category": .bool(true)]) { _, new in new }] {
            var changed = state
            try DesktopPatches.apply([.object(["op": .string("replace"),
                "path": .array([.string("turns"), .integer(0), .string("params"), .string("approvalPolicy")]),
                "value": .object(["granular": .object(changedFlags)])])], to: &changed)
            #expect(throws: (any Error).self) { _ = try approvals(changed) }
        }
        var command = approvalState()
        let commandFlags = flags.merging(["sandbox_approval": .bool(true), "rules": .bool(true)]) { _, new in new }
        try DesktopPatches.apply([.object(["op": .string("replace"),
            "path": .array([.string("turns"), .integer(0), .string("params"), .string("approvalPolicy")]),
            "value": .object(["granular": .object(commandFlags)])])], to: &command)
        #expect(try approvals(command).first?.responses["accept"] == .string("accept"))
        for disabled in ["sandbox_approval", "rules"] {
            var changed = command
            try DesktopPatches.apply([.object(["op": .string("replace"),
                "path": .array([.string("turns"), .integer(0), .string("params"), .string("approvalPolicy"), .string("granular"), .string(disabled)]),
                "value": .bool(false)])], to: &changed)
            #expect(throws: (any Error).self) { _ = try approvals(changed) }
        }
    }
    @Test(arguments: ["computer-use", "browser-use"]) func elicitationKeepsNativeScopeAndDenyPayload(connector: String) throws {
        var state = approvalState()
        let meta = JSONValue.object(["codex_approval_kind": .string("mcp_tool_call"), "connector_id": .string(connector),
            "tool_name": .string(connector == "computer-use" ? "get_app_state" : "access_browser_origin_with_raw_cdp"),
            "subtitle": .string("Source-provided access warning"), "riskLevel": .string("high"),
            "persist": .array([.string("session"), .string("always")]),
            "tool_params": .object(connector == "computer-use" ? ["app": .string("com.example.Test")] : ["origin": .string("https://example.com")])])
        let params = JSONValue.object(["threadId": .string("thread"), "turnId": .string("turn"), "mode": .string("form"),
            "message": .string("Allow this test?"), "_meta": meta,
            "requestedSchema": .object(["type": .string("object"), "properties": .object([:])])])
        try DesktopPatches.apply([.object(["op": .string("replace"), "path": .array([.string("requests")]),
            "value": .array([.object(["id": .string("native-permission"), "method": .string("mcpServer/elicitation/request"), "params": params])])])], to: &state)
        let pending = try #require(approvals(state).first)
        #expect(pending.method == "thread-follower-submit-mcp-server-elicitation-response")
        #expect(pending.responses["session"]?["_meta"]["persist"] == .string("session"))
        #expect(pending.responses["always"]?["_meta"]["persist"] == .string("always"))
        #expect(pending.responses["deny"] == .object(["action": .string("decline"), "content": .null, "_meta": .null]))
        #expect(pending.responses["once"] == nil)
        #expect(pending.request.approvalDetails?.persistentActions["always"] == .savedPermission)
        let display = try JSONValue.parse(JSONEncoder().encode(pending.request.approvalDetails))
        let notices = ["Source-provided access warning", "Source risk: high"]
            + (connector == "browser-use" ? ["Requests direct browser control."] : [])
        #expect(display["subject"]["access"]["notices"] == .array(notices.map(JSONValue.string)))
        for (field, value): (String, JSONValue) in [("allOf", .array([.object(["required": .array([.string("confirmation")])])])), ("minProperties", .integer(1))] {
            var changed = state
            try DesktopPatches.apply([.object(["op": .string("add"),
                "path": .array([.string("requests"), .integer(0), .string("params"), .string("requestedSchema"), .string(field)]), "value": value])], to: &changed)
            #expect(throws: (any Error).self) { _ = try approvals(changed) }
        }
        if connector == "browser-use" {
            for tool: JSONValue in [.null, .string("future_browser_tool")] {
                var changed = state
                try DesktopPatches.apply([.object(["op": .string("replace"),
                    "path": .array([.string("requests"), .integer(0), .string("params"), .string("_meta"), .string("tool_name")]), "value": tool])], to: &changed)
                #expect(throws: (any Error).self) { _ = try approvals(changed) }
            }
        }
        try DesktopPatches.apply([.object(["op": .string("add"),
            "path": .array([.string("requests"), .integer(0), .string("params"), .string("requestedSchema"), .string("properties"), .string("unknownField")]),
            "value": .object(["type": .string("string")])])], to: &state)
        #expect(throws: (any Error).self) { _ = try approvals(state) }
    }
    @Test func approvalsStayIndependentFromIncompleteQuestionHistory() async throws {
        var state = approvalState()
        try DesktopPatches.apply([.object(["op": .string("add"),
            "path": .array([.string("turns"), .integer(0), .string("itemsPagination")]),
            "value": .object(["hasLoadedOldest": .bool(false)])])], to: &state)
        let server = try FixtureDesktopServer(state: state); defer { server.stop() }
        let core = RequestController(ledger: MemoryLedger()), adapter = DesktopAdapter(directory: server.directory, controller: core)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await core.snapshot().contains { $0.state == .pending } }
        let view = try #require(await core.snapshot().first)
        #expect(view.id.scope.installation.hasSuffix(":approvals"))
        // A new native target with the same ID invalidates the old displayed fingerprint.
        server.state = approvalState(extra: ["approvalId": .string("replaced")])
        try await eventually { await core.snapshot().first?.request.fingerprint != view.request.fingerprint }
        await #expect(throws: ResponseError.self) {
            try await core.respond(key: view.id, fingerprint: view.request.fingerprint, answer: .decision("accept"), using: adapter)
        }
        #expect(server.answers.isEmpty)
        server.state = approvalState(reviewer: "auto_review")
        try await eventually { await adapter.health().needsSourceApproval }
        #expect(await core.snapshot().allSatisfy { $0.state == .unavailable })
        await adapter.stop()
        #expect(await adapter.health().needsSourceApproval == false)
    }
}
