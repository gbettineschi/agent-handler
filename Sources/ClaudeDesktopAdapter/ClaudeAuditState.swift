import Foundation
import CoreFoundation
import CryptoKit
import AgentHandlerCore

/// Ordered local-runtime audit facts only. These records never authorize a response.
struct ClaudeAuditState: Sendable {
    private struct Turn: Sendable {
        let id: String
        let session: String
        var phase: ActivityPhase = .running
        var permissions: Set<String> = []
    }
    private var turn: Turn?
    private var seen: [String: String] = [:]
    private(set) var isKnown = false
    var observation: (turnID: String, phase: ActivityPhase, attention: ActivityAttention)? {
        guard isKnown, let turn else { return nil }
        return (turn.id, turn.phase, turn.permissions.isEmpty ? .clear : .required)
    }
    mutating func invalidate() { turn = nil; isKnown = false }

    mutating func consume(_ line: Data) {
        guard line.count <= 512 * 1024,
              let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = record["type"] as? String else { invalidate(); return }
        if let parent = record["parent_tool_use_id"], !(parent is NSNull) {
            guard let id = parent as? String, !id.isEmpty else { invalidate(); return }
            return // A child cannot complete the main turn or withdraw its permissions.
        }
        if ["assistant", "user", "stream_event", "rate_limit_event", "tool_progress", "tool_use_summary"].contains(type) { return }
        let subtype = record["subtype"] as? String
        if type == "system", let subtype,
           ["status", "thinking_tokens", "hook_started", "hook_progress", "hook_response", "compact_boundary",
            "task_notification", "task_started", "task_progress", "files_persisted", "local_command",
            "permission_auto_approved", "permission_auto_denied"].contains(subtype) { return }
        guard type == "result" || (type == "system" && ["init", "permission_request", "permission_response"].contains(subtype ?? "")),
              let id = identifier(record["uuid"]), let session = identifier(record["session_id"]) else { invalidate(); return }
        let key = "\(type):\(subtype ?? ""):\(id)"
        let fingerprint = SHA256.hash(data: line).map { String(format: "%02x", $0) }.joined()
        if let previous = seen[key] {
            if previous != fingerprint { invalidate() }
            return
        }
        if seen.count >= 1024 {
            invalidate()
            guard type == "system", subtype == "init" else { return }
            seen.removeAll(keepingCapacity: true)
        }
        seen[key] = fingerprint
        if type == "system", subtype == "init" {
            turn = Turn(id: id, session: session); isKnown = true
            return
        }
        guard isKnown, var active = turn, active.session == session else { invalidate(); return }
        if type == "system" {
            if subtype == "permission_request" {
                guard active.phase == .running, identifier(record["tool_name"]) != nil,
                      active.permissions.count < 128 else { invalidate(); return }
                active.permissions.insert(id)
            } else { active.permissions.remove(id) }
        } else {
            guard active.phase == .running, let error = strictBool(record["is_error"]),
                  let reason = record["terminal_reason"] as? String, !reason.isEmpty else { invalidate(); return }
            if subtype == "success", !error, reason == "completed" { active.phase = .completed }
            else if subtype?.hasPrefix("error_") == true, error {
                if ["aborted_streaming", "aborted_tools"].contains(reason) { active.phase = .cancelled }
                else if reason.hasPrefix("aborted_") { invalidate(); return }
                else { active.phase = .failed }
            } else { invalidate(); return }
            active.permissions = []
        }
        turn = active
    }

    private func identifier(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.utf8.count <= 256 else { return nil }
        return text
    }
    private func strictBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
