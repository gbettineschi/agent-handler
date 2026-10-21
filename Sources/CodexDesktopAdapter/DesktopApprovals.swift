// Native elicitation mappings adapted from Agent HUD Open, Apache-2.0; see THIRD_PARTY_NOTICES.md.
import Foundation
import AgentHandlerCore

/// Approval identity and decisions come from the owner's pending requests, never transcript tool calls.
enum DesktopApprovals {
    struct Pending: Sendable {
        let request: AttentionRequest
        let wireID: JSONValue
        let method: String
        let parameter: String
        let responses: [String: JSONValue]
    }
    enum Failure: Error { case unsupported }
    static func installation(_ base: String) -> String { base + ":approvals" }

    static func pending(state: JSONValue, threadID: String, owner: String, installation: String) throws -> [Pending] {
        guard let requests = state["requests"].arrayValue else { throw Failure.unsupported }
        var found: [Pending] = []
        for wire in requests {
            guard wire.objectValue != nil, let kind = wire["method"].stringValue else { throw Failure.unsupported }
            guard ["item/commandExecution/requestApproval", "mcpServer/elicitation/request"].contains(kind) else { continue }
            if wire["completed"] == .bool(true) { continue }
            guard wire["completed"] == .null || wire["completed"] == .bool(false), complete(wire) else { throw Failure.unsupported }
            let params = wire["params"]
            guard params["threadId"].stringValue == threadID else { throw Failure.unsupported }
            let id: NativeID
            switch wire["id"] {
            case .string(let value) where !value.isEmpty: id = .string(value)
            case .integer(let value): id = .integer(value)
            default: throw Failure.unsupported
            }
            let turnID = params["turnId"].stringValue
            let turn = try turnID.flatMap { try DesktopQuestions.turn($0, in: state) }
            let settings = try effectiveSettings(turn?["params"].objectValue == nil ? state["currentPermissions"] : turn!["params"])
            // Never show the automatic review queue as a human permission prompt.
            guard settings["approvalsReviewer"].stringValue == "user" else { throw Failure.unsupported }
            if let granular = settings["approvalPolicy"]["granular"].objectValue {
                // The wire request does not identify whether a command prompt came from
                // the sandbox or an execpolicy rule. Require both categories in that case.
                let categories = kind == "item/commandExecution/requestApproval"
                    ? ["sandbox_approval", "rules"] : ["mcp_elicitations"]
                guard categories.allSatisfy({ granular[$0] == .bool(true) }) else { throw Failure.unsupported }
            }
            var title: String, method: String, parameter: String
            var subject: ApprovalDetails.Subject?
            var persistentActions: [String: ApprovalDetails.PersistentAction] = [:]
            var responses: [String: JSONValue] = [:], options: [ResponseOption] = []
            if kind == "item/commandExecution/requestApproval" {
                guard let turnID, !turnID.isEmpty, turn?["status"].stringValue == "inProgress",
                      params["itemId"].stringValue?.isEmpty == false,
                      let command = params["command"].stringValue, !command.isEmpty,
                      let cwd = params["cwd"].stringValue, !cwd.isEmpty,
                      params["networkApprovalContext"] == .null, params["additionalPermissions"] == .null else { throw Failure.unsupported }
                let labels = ["accept": "Allow once", "acceptForSession": "Allow for this session", "decline": "Deny", "cancel": "Cancel turn"]
                let decisions: [JSONValue]
                if params["availableDecisions"] == .null { decisions = ["accept", "acceptForSession", "decline", "cancel"].map(JSONValue.string) }
                else { guard let values = params["availableDecisions"].arrayValue, !values.isEmpty else { throw Failure.unsupported }; decisions = values }
                guard decisions.count <= 16 else { throw Failure.unsupported }
                for (index, decision) in decisions.enumerated() {
                    let name: String, label: String
                    if let value = decision.stringValue, let text = labels[value] { name = value; label = text }
                    else if let object = decision.objectValue, Set(object.keys) == ["acceptWithExecpolicyAmendment"],
                            let amendment = object["acceptWithExecpolicyAmendment"]?.objectValue,
                            Set(amendment.keys) == ["execpolicy_amendment"],
                            let prefix = amendment["execpolicy_amendment"]?.arrayValue, !prefix.isEmpty, prefix.count <= 64,
                            prefix.allSatisfy({ $0.stringValue?.isEmpty == false }) {
                        let text = String(decoding: try RecordCoding.encoder().encode(JSONValue.array(prefix)), as: UTF8.self)
                        guard text.utf8.count <= 4096 else { throw Failure.unsupported }
                        name = "command-rule-\(index)"; label = "Allow and save command rule: \(text)"
                        persistentActions[name] = .commandRule(prefix: prefix.compactMap(\.stringValue))
                    } else { throw Failure.unsupported }
                    guard responses[name] == nil, !responses.values.contains(decision) else { throw Failure.unsupported }
                    responses[name] = decision; options.append(.init(id: name, label: label))
                }
                title = "Run command?\n\n\(command)\n\nDirectory: \(cwd)"
                if params["reason"] != .null { guard let reason = params["reason"].stringValue else { throw Failure.unsupported }; title += "\n\n\(reason)" }
                subject = .command(command: command, directory: cwd, reason: params["reason"].stringValue)
                method = "thread-follower-command-approval-decision"; parameter = "decision"
            } else {
                let meta = params["_meta"]
                guard meta["codex_approval_kind"].stringValue == "mcp_tool_call",
                      ["computer-use", "browser-use"].contains(meta["connector_id"].stringValue ?? "") else { continue }
                guard params["mode"].stringValue == "form", let message = params["message"].stringValue, !message.isEmpty,
                      let schema = params["requestedSchema"].objectValue,
                      Set(schema.keys).isSubset(of: ["type", "properties", "required", "additionalProperties"]),
                      params["requestedSchema"]["type"].stringValue == "object",
                      params["requestedSchema"]["properties"].objectValue?.isEmpty == true,
                      params["requestedSchema"]["required"] == .null || params["requestedSchema"]["required"] == .array([]) else { throw Failure.unsupported }
                if let additional = schema["additionalProperties"], additional != .bool(false), additional != .bool(true) { throw Failure.unsupported }
                let persist: [String]
                switch meta["persist"] {
                case .null: persist = []
                case .string(let value): persist = [value]
                case .array(let values):
                    guard values.allSatisfy({ $0.stringValue != nil }) else { throw Failure.unsupported }
                    persist = values.compactMap(\.stringValue)
                default: throw Failure.unsupported
                }
                guard Set(persist).count == persist.count, persist.allSatisfy({ ["session", "always"].contains($0) }) else { throw Failure.unsupported }
                if meta["connector_id"].stringValue == "computer-use" {
                    guard meta["tool_params"]["app"].stringValue?.isEmpty == false, persist.contains("session") else { throw Failure.unsupported }
                }
                if meta["connector_id"].stringValue == "browser-use" {
                    guard ["access_browser_origin", "access_browser_origin_with_raw_cdp"].contains(meta["tool_name"].stringValue ?? "") else { throw Failure.unsupported }
                    if settings["approvalPolicy"].stringValue == "never", settings["sandboxPolicy"]["type"].stringValue == "dangerFullAccess" { throw Failure.unsupported }
                }
                let allowed = persist.contains("session") ? [("session", "Allow for this conversation")] : [("", "Allow once")]
                for (scope, label) in allowed + (persist.contains("always") ? [("always", "Always allow")] : []) {
                    let name = scope.isEmpty ? "once" : scope
                    responses[name] = .object(["action": .string("accept"), "content": .object([:]),
                        "_meta": scope.isEmpty ? .null : .object(["persist": .string(scope)])])
                    options.append(.init(id: name, label: label))
                }
                responses["deny"] = .object(["action": .string("decline"), "content": .null, "_meta": .null])
                options.append(.init(id: "deny", label: "Deny"))
                title = message
                var notices: [String] = []
                for field in ["subtitle", "riskLevel"] where meta[field] != .null {
                    guard let value = meta[field].stringValue else { throw Failure.unsupported }; title += "\n\n\(value)"
                    if !value.isEmpty { notices.append(field == "riskLevel" ? "Source risk: \(value)" : value) }
                }
                if meta["tool_name"].stringValue == "access_browser_origin_with_raw_cdp" {
                    notices.append("Requests direct browser control.")
                }
                if meta["tool_params"] != .null { title += "\n\n" + String(decoding: try RecordCoding.encoder().encode(meta["tool_params"]), as: UTF8.self) }
                let app = meta["connector_id"].stringValue == "computer-use"
                subject = .access(message: message, targetLabel: app ? "App" : "Website",
                    target: meta["tool_params"][app ? "app" : "origin"].stringValue ?? "", notices: notices, technicalDetails: title)
                if persist.contains("always") { persistentActions["always"] = .savedPermission }
                method = "thread-follower-submit-mcp-server-elicitation-response"; parameter = "response"
            }
            guard title.utf8.count <= 16_384 else { throw Failure.unsupported }
            let source = try [wire, settings].map { String(decoding: try RecordCoding.encoder().encode($0), as: UTF8.self) }
            let request = AttentionRequest(key: .init(scope: .init(installation: Self.installation(installation), conversation: threadID), turn: turnID, nativeID: id),
                owner: owner, title: title, content: .approval(choices: options), sourceFingerprint: RecordCoding.hash(source),
                approvalDetails: subject.map { ApprovalDetails(subject: $0, persistentActions: persistentActions) })
            found.append(.init(request: request, wireID: wire["id"], method: method, parameter: parameter, responses: responses))
        }
        guard found.count <= 128, Set(found.map { $0.request.key }).count == found.count else { throw Failure.unsupported }
        return found
    }
    /// Retain only relevant settings: unrelated turn metadata was intentionally projected away.
    /// Missing/oversized permission data must never look like an explicit null/default policy.
    private static func effectiveSettings(_ raw: JSONValue) throws -> JSONValue {
        let settings = JSONValue.object(Dictionary(uniqueKeysWithValues:
            ["approvalsReviewer", "approvalPolicy", "sandboxPolicy"].map { ($0, raw[$0]) }))
        guard complete(settings), settings["approvalsReviewer"].stringValue == "user",
              let sandbox = settings["sandboxPolicy"].objectValue,
              let kind = sandbox["type"]?.stringValue else { throw Failure.unsupported }
        if let policy = settings["approvalPolicy"].stringValue {
            guard ["untrusted", "on-failure", "on-request", "never"].contains(policy) else { throw Failure.unsupported }
        } else {
            let categories: Set<String> = ["sandbox_approval", "rules", "skill_approval", "request_permissions", "mcp_elicitations"]
            guard let policy = settings["approvalPolicy"].objectValue, Set(policy.keys) == ["granular"],
                  let granular = policy["granular"]?.objectValue, Set(granular.keys) == categories,
                  granular.values.allSatisfy({ $0 == .bool(true) || $0 == .bool(false) }) else { throw Failure.unsupported }
        }
        let allowed: Set<String>
        switch kind {
        case "dangerFullAccess": allowed = ["type"]
        case "readOnly": allowed = ["type", "networkAccess"]
        case "workspaceWrite":
            allowed = ["type", "writableRoots", "networkAccess", "excludeTmpdirEnvVar", "excludeSlashTmp"]
            guard let roots = sandbox["writableRoots"]?.arrayValue,
                  roots.allSatisfy({ $0.stringValue?.isEmpty == false }) else { throw Failure.unsupported }
        default: throw Failure.unsupported
        }
        guard Set(sandbox.keys).isSubset(of: allowed) else { throw Failure.unsupported }
        for key in ["networkAccess", "excludeTmpdirEnvVar", "excludeSlashTmp"] {
            if let value = sandbox[key], value != .bool(true), value != .bool(false) { throw Failure.unsupported }
        }
        return settings
    }
    private static func complete(_ value: JSONValue) -> Bool {
        switch value {
        case .omitted, .discarded: false
        case .object(let values): values.values.allSatisfy(complete)
        case .array(let values): values.allSatisfy(complete)
        default: true
        }
    }
}

extension DesktopApprovals {
    static func deliver(_ attempt: ResponseAttempt, directory: URL, stream: DesktopStream, installation: String, didWrite: @escaping () -> Void) throws -> DeliveryOutcome {
        guard case .decision(let decision) = attempt.answer else { return .notSent }
        let request = attempt.request, threadID = request.key.scope.conversation
        let wire = try DesktopIPC(path: directory.appendingPathComponent("ipc/ipc.sock").path, timeout: 10)
        defer { wire.close() }
        let initialized = try wire.request(method: "initialize", version: 0, source: "initializing-client", params: ["clientType": "agent-handler"])
        guard let client = (initialized["result"] as? [String: Any])?["clientId"] as? String, !client.isEmpty else { return .notSent }
        let discovered = try wire.request(method: "thread-owner-discovery", version: 1, source: client, params: ["hostId": "local", "conversationId": threadID])
        guard discovered["handledByClientId"] as? String == request.owner,
              let current = stream.thread(threadID), current.ownerClientID == request.owner,
              let pending = try Self.pending(state: current.state, threadID: threadID, owner: request.owner, installation: installation).first(where: { $0.request == request }),
              let response = pending.responses[decision] else { return .notSent }
        let params = JSONValue.object(["conversationId": .string(threadID), "requestId": pending.wireID, pending.parameter: response])
        guard let encoded = try JSONSerialization.jsonObject(with: RecordCoding.encoder().encode(params)) as? [String: Any] else { return .notSent }
        try Task.checkCancellation()
        let receipt = try wire.request(method: pending.method, version: 1, source: client, target: request.owner, params: encoded, didWrite: didWrite)
        let value = try JSONValue.parse(JSONSerialization.data(withJSONObject: receipt))
        guard value["handledByClientId"].stringValue == request.owner,
              value["result"]["method"].stringValue == pending.method,
              value["result"]["result"]["ok"] == .bool(true) else { return .uncertain }
        // This host returns ok even if a concurrent cancellation removed the native request.
        // Authoritative withdrawal will close the card; dispatch alone never proves a decision.
        return .uncertain
    }
}
