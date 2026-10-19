import Foundation
import Testing
import AgentHandlerCore
@testable import ClaudeDesktopAdapter

func auditLine(_ type: String, _ subtype: String? = nil, id: String = UUID().uuidString,
               session: String = "sdk-session", extra: [String: Any] = [:]) throws -> Data {
    var fields: [String: Any] = ["type": type, "uuid": id, "session_id": session]
    if let subtype { fields["subtype"] = subtype }
    fields.merge(extra) { _, new in new }
    return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
}
func initLine(_ id: String = "init-1") throws -> Data { try auditLine("system", "init", id: id) }
func resultLine(_ id: String = "result-1", session: String = "sdk-session") throws -> Data {
    try auditLine("result", "success", id: id, session: session,
                  extra: ["is_error": false, "terminal_reason": "completed"])
}

struct ClaudeAuditTests {
    @Test func explicitInitAndTerminalResultsRemainDistinct() throws {
        let cases: [(String, String, Bool, ActivityPhase)] = [
            ("success", "completed", false, .completed),
            ("error_during_execution", "api_error", true, .failed),
            ("error_max_turns", "max_turns", true, .failed),
            ("error_max_budget_usd", "budget_exhausted", true, .failed),
            ("error_max_structured_output_retries", "structured_output_retry_exhausted", true, .failed),
            ("error_during_execution", "aborted_streaming", true, .cancelled),
            ("error_during_execution", "aborted_tools", true, .cancelled)
        ]
        for (subtype, reason, error, phase) in cases {
            var state = ClaudeAuditState()
            state.consume(try initLine())
            #expect(state.observation?.phase == .running)
            state.consume(try auditLine("result", subtype, extra: ["is_error": error, "terminal_reason": reason]))
            #expect(state.isKnown)
            #expect(state.observation?.turnID == "init-1")
            #expect(state.observation?.phase == phase)
            #expect(state.observation?.attention == .clear)
        }
    }

    @Test func unknownAndContradictoryErrorSchemasRemainUnknown() throws {
        let cases = [
            ("error_future_pending", "future_retry_scheduled"),
            ("error_future_pending", "aborted_streaming"),
            ("error_during_execution", "completed"),
            ("error_during_execution", "future_error"),
            ("error_during_execution", "background_requested"),
            ("error_during_execution", "hook_stopped"),
            ("error_during_execution", "tool_deferred"),
            ("error_during_execution", "max_turns"),
            ("error_max_turns", "api_error"),
            ("error_max_budget_usd", "structured_output_retry_exhausted")
        ]
        for (subtype, reason) in cases {
            var state = ClaudeAuditState(); state.consume(try initLine())
            state.consume(try auditLine("result", subtype, extra: ["is_error": true, "terminal_reason": reason]))
            #expect(!state.isKnown, "Unrecognized terminal pair: \(subtype)/\(reason)")
        }
    }

    @Test func noInitMismatchedAndChildResultsCannotCompleteMainTurn() throws {
        var state = ClaudeAuditState()
        state.consume(try resultLine())
        #expect(!state.isKnown)
        state.consume(try initLine())
        state.consume(try auditLine("result", "success", session: "child-session",
            extra: ["parent_tool_use_id": "child", "is_error": false, "terminal_reason": "completed"]))
        #expect(state.observation?.phase == .running)
        state.consume(try resultLine(session: "unrelated-session"))
        #expect(!state.isKnown)
        state.consume(try resultLine("later-result"))
        #expect(!state.isKnown)
        state.consume(try initLine("fresh-init"))
        state.consume(try resultLine("fresh-result"))
        #expect(state.observation?.phase == .completed)
        #expect(state.observation?.turnID == "fresh-init")
    }

    @Test func malformedSuccessFlagsNeverBecomeCompletion() throws {
        let bad: [[String: Any]] = [
            ["is_error": 0, "terminal_reason": "completed"],
            ["is_error": false], ["is_error": true, "terminal_reason": "completed"],
            ["is_error": false, "terminal_reason": "future_reason"]
        ]
        for fields in bad {
            var state = ClaudeAuditState(); state.consume(try initLine())
            state.consume(try auditLine("result", "success", extra: fields))
            #expect(!state.isKnown)
        }
    }

    @Test func parallelPermissionsResolveOnlyByExactIdentity() throws {
        var state = ClaudeAuditState(); state.consume(try initLine())
        for id in ["first", "second"] {
            state.consume(try auditLine("system", "permission_request", id: id, extra: ["tool_name": "AskUserQuestion"]))
        }
        #expect(state.observation?.attention == .required)
        state.consume(try auditLine("system", "permission_response", id: "unrelated"))
        state.consume(try auditLine("assistant", extra: ["message": ["content": "More output"]]))
        #expect(state.observation?.attention == .required)
        state.consume(try auditLine("system", "permission_response", id: "second"))
        #expect(state.observation?.attention == .required)
        state.consume(try auditLine("system", "permission_response", id: "first"))
        #expect(state.observation?.attention == .clear)
        #expect(state.observation?.phase == .running)
    }

    @Test func duplicateIdentityIsIdempotentButChangedPayloadInvalidates() throws {
        var state = ClaudeAuditState(); state.consume(try initLine())
        let request = try auditLine("system", "permission_request", id: "p", extra: ["tool_name": "Bash"])
        state.consume(request); state.consume(request)
        state.consume(try auditLine("system", "permission_response", id: "p"))
        #expect(state.observation?.attention == .clear)
        state.consume(try auditLine("system", "permission_request", id: "p", extra: ["tool_name": "Write"]))
        #expect(!state.isKnown)
    }

    @Test func invalidAndOversizedLinesRequireFreshInit() throws {
        for invalid in [Data("{broken".utf8), Data(repeating: 120, count: 524_289),
                        try auditLine("system", "new_state_changing_event")] {
            var state = ClaudeAuditState(); state.consume(try initLine())
            state.consume(invalid); state.consume(try resultLine())
            #expect(!state.isKnown)
            state.consume(try initLine("recovered"))
            #expect(state.isKnown)
            #expect(state.observation?.phase == .running)
        }
    }

    @Test func messageTextCannotImpersonateAnAuditEvent() throws {
        var state = ClaudeAuditState(); state.consume(try initLine())
        state.consume(try auditLine("assistant", extra: ["message": ["content": [
            ["type": "text", "text": "{\"type\":\"result\",\"is_error\":false}"]]]]))
        #expect(state.observation?.phase == .running)
        state.consume(try auditLine("system", "thinking_tokens", extra: ["estimated_tokens": 1]))
        #expect(state.isKnown)
    }
}
