// Adapted from Agent HUD Open, Apache-2.0. See THIRD_PARTY_NOTICES.md.
import Foundation
import AgentHandlerCore

public enum DesktopQuestions {
    public enum Failure: Error { case unsupported }
    // Discriminators observed on the pinned Desktop build. New kinds require a compatibility check.
    private static let knownItems: Set<String> = ["agentMessage", "automaticApprovalReview", "collabAgentToolCall",
        "commandExecution", "contextCompaction", "fileChange", "forkedFromConversation", "functionCallOutput", "imageView", "mcpServerElicitation",
        "mcpToolCall", "modelChanged", "reasoning", "sleep", "steered", "steeringUserMessage", "subAgentActivity",
        "userMessage", "webSearch"]
    public static func decode(_ data: Data, threadID: String, owner: String, installation: String) throws -> [AttentionRequest] {
        guard data.count <= 128 * 1024 * 1024 else { throw Failure.unsupported }
        return try parse(state: JSONValue.parse(data, leavingOutStringsOver: 16_384), threadID: threadID, owner: owner, installation: installation)
    }
    static func parse(state: JSONValue, threadID: String, owner: String, installation: String) throws -> [AttentionRequest] {
        let history = try turns(state)
        var hasOldest = true
        if state["turnHistory"]["kind"].stringValue == "canonical" {
            let islands = state["turnHistory"]["history"]["islands"].arrayValue ?? []
            guard islands.count == 1, let island = islands.first,
                  island["newerBoundary"]["status"].stringValue == "exhausted",
                  (state["turns"].arrayValue ?? []).isEmpty else { throw Failure.unsupported }
            hasOldest = island["olderBoundary"]["status"].stringValue == "exhausted"
        }
        var candidates: [JSONValue] = []
        for (index, turn) in history.enumerated().reversed() {
            guard ["inProgress", "completed"].contains(turn["status"].stringValue ?? "") else { break }
            guard turn["itemsPagination"]["hasLoadedOldest"] != .bool(false),
                  turn["itemsPagination"]["isLoadingOlder"] != .bool(true) else { throw Failure.unsupported }
            candidates.append(turn)
            guard let items = turn["items"].arrayValue else { throw Failure.unsupported }
            let userItems = items.filter { $0["type"].stringValue == "userMessage" ||
                ($0["type"].stringValue == "steeringUserMessage" && $0["status"].stringValue == "accepted") }
            for item in userItems {
                let content = item[item["type"].stringValue == "userMessage" ? "content" : "input"]
                guard let parts = content.arrayValue, !parts.isEmpty, parts.allSatisfy({
                    guard $0.objectValue != nil, let type = $0["type"].stringValue else { return false }
                    switch type {
                    case "text": return $0["text"].stringValue != nil
                    case "localImage": return $0["path"].stringValue?.isEmpty == false
                    default: return false
                    }
                }) else { throw Failure.unsupported }
            }
            // Native answer-only follow-ups and tool continuations keep an earlier group current.
            // An unrelated prompt ends that group; never resurrect arbitrary historical questions.
            if userItems.isEmpty {
                if index == 0 {
                    guard hasOldest else { throw Failure.unsupported }
                    break
                }
                // Desktop can resume a turn through its chat-management tool. The tool result
                // has no user-answer authority and cannot end an earlier question group. Follow
                // the complete history back to a native user boundary instead of losing liveness.
                guard items.contains(where: { $0["type"].stringValue == "functionCallOutput" }) else { throw Failure.unsupported }
                continue
            }
            guard userItems.allSatisfy({ !answeredQuestionIDs($0).isEmpty }) else { break }
            if index == 0, !hasOldest { throw Failure.unsupported }
        }
        let answered = Set(candidates.flatMap { ($0["items"].arrayValue ?? []).flatMap(answeredQuestionIDs) })
        let requests = try candidates.reversed().flatMap {
            try questions(in: $0, answered: answered, threadID: threadID, owner: owner, installation: installation)
        }
        guard requests.count <= 128, Set(requests.map(\.key)).count == requests.count else { throw Failure.unsupported }
        return requests
    }
    private static func questions(in turn: JSONValue, answered: Set<String>, threadID: String, owner: String, installation: String) throws -> [AttentionRequest] {
        guard let turnID = turn["turnId"].stringValue, !turnID.isEmpty,
              let items = turn["items"].arrayValue else { throw Failure.unsupported }
        guard items.allSatisfy({ item in
            guard item.objectValue != nil, let kind = item["type"].stringValue, knownItems.contains(kind) else { return false }
            return kind != "agentMessage" || item["id"].stringValue?.isEmpty == false
        }) else { throw Failure.unsupported }
        for item in items where item["type"].stringValue == "userMessage" || item["type"].stringValue == "steeringUserMessage" {
            let content = item["type"].stringValue == "userMessage" ? item["content"] : item["input"]
            if content.arrayValue?.contains(where: { $0["type"].stringValue == "text" && $0["text"] == .omitted }) == true { throw Failure.unsupported }
        }
        var requests: [AttentionRequest] = []
        for item in items where item["type"].stringValue == "agentMessage" && item["questions"] != .null {
            guard let sourceID = item["id"].stringValue, !sourceID.isEmpty,
                  let questions = item["questions"].arrayValue else { throw Failure.unsupported }
            for (index, raw) in questions.enumerated() {
                guard let fields = raw.objectValue, Set(fields.keys).isSubset(of: ["title", "options"]),
                      let title = raw["title"].stringValue, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      title.utf8.count <= 16_384 else { throw Failure.unsupported }
                let labels: [String]
                if raw["options"] == .null { labels = [] }
                else {
                    guard let options = raw["options"].arrayValue, options.count <= 128,
                          options.allSatisfy({ $0.stringValue?.isEmpty == false }) else { throw Failure.unsupported }
                    labels = options.compactMap(\.stringValue)
                }
                let identity = JSONValue.array([.string("request_user_input_async"), .string(sourceID), .integer(Int64(index))])
                let nativeID = String(decoding: try RecordCoding.encoder().encode(identity), as: UTF8.self)
                if answered.contains(nativeID) { continue }
                requests.append(AttentionRequest(key: .init(scope: .init(installation: installation, conversation: threadID), turn: turnID, nativeID: .string(nativeID)), owner: owner, title: title,
                    content: .question(options: labels.enumerated().map { .init(id: String($0.offset), label: $0.element) }, allowsText: true)))
            }
        }
        return requests
    }
    /// The owner steers its latest real turn, or an unfinished placeholder awaiting a turn ID.
    static func currentTurnID(_ state: JSONValue) throws -> String? {
        // Desktop's current-turn selector reads the canonical store itself, rather than its display overlay.
        try turns(state, includeOverlay: false).last(where: {
            $0["turnId"] != .null || ($0["status"].stringValue != "completed" && $0["status"].stringValue != "failed")
        })?["turnId"].stringValue
    }

    /// The turn of that id as the state holds it, for what it was started with.
    static func turn(_ id: String, in state: JSONValue) throws -> JSONValue? {
        try turns(state).last { $0["turnId"].stringValue == id }
    }

    // Shared structural decoding; callers still establish their own history/attention requirements.
    static func turns(_ state: JSONValue, includeOverlay: Bool = true) throws -> [JSONValue] {
        guard let fields = state.objectValue else { throw Failure.unsupported }
        let overlay: [JSONValue]
        if let value = fields["turns"] {
            guard let values = value.arrayValue, values.allSatisfy({ $0.objectValue != nil }) else {
                throw Failure.unsupported
            }
            overlay = values
        } else {
            // Permission-only snapshots and fixtures do not carry any turn store.
            guard fields["turnHistory"] != nil else { throw Failure.unsupported }
            overlay = []
        }
        guard let storage = fields["turnHistory"], storage != .null else {
            guard fields["turns"] != nil else { throw Failure.unsupported }
            return try validatedTurns(overlay)
        }
        guard storage.objectValue != nil else { throw Failure.unsupported }
        guard storage["kind"].stringValue == "canonical" else { throw Failure.unsupported }
        let history = storage["history"]
        guard let islands = history["islands"].arrayValue,
              let entities = history["entitiesByKey"].objectValue else { throw Failure.unsupported }
        var canonical: [JSONValue] = []
        for island in islands {
            guard let entries = island["entries"].arrayValue else { throw Failure.unsupported }
            for entry in entries {
                guard let key = entry["value"].stringValue, let turn = entities[key], turn.objectValue != nil else {
                    throw Failure.unsupported
                }
                canonical.append(turn)
            }
        }
        // Desktop's canonical store normally clears legacy turns. Disjoint overlay turns append in its merge;
        // overlapping stores need Desktop's full rendering merge, so they cannot safely establish withdrawal here.
        let canonicalIDs = Set(canonical.compactMap { $0["turnId"].stringValue })
        guard !overlay.contains(where: { $0["turnId"].stringValue.map(canonicalIDs.contains) == true }) else {
            throw Failure.unsupported
        }
        return try validatedTurns(includeOverlay ? canonical + overlay : canonical)
    }

    private static func validatedTurns(_ turns: [JSONValue]) throws -> [JSONValue] {
        let statuses: Set<String> = ["inProgress", "completed", "failed", "interrupted"]
        guard turns.allSatisfy({ turn in
            guard turn.objectValue != nil, let id = turn["turnId"].stringValue, !id.isEmpty,
                  let status = turn["status"].stringValue, statuses.contains(status) else { return false }
            return status != "inProgress" || turn["items"].arrayValue != nil
        }), turns.filter({ $0["status"].stringValue == "inProgress" }).count <= 1 else { throw Failure.unsupported }
        return turns
    }

    private static func answeredQuestionIDs(_ item: JSONValue) -> [String] {
        let content: JSONValue
        switch item["type"].stringValue {
        case "userMessage": content = item["content"]
        case "steeringUserMessage" where item["status"].stringValue == "accepted": content = item["input"]
        default: return []
        }
        guard let parts = content.arrayValue, parts.count == 1, parts[0]["type"].stringValue == "text",
              let text = parts[0]["text"].stringValue else { return [] }
        let opening = "<send_user_message_question_reply>", closing = "</send_user_message_question_reply>"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(opening), trimmed.hasSuffix(closing) else { return [] }
        let payload = trimmed.dropFirst(opening.count).dropLast(closing.count)
        guard let value = try? JSONValue.parse(Data(payload.utf8)) else { return [] }
        let answers: [JSONValue]
        if let array = value.arrayValue, !array.isEmpty { answers = array }
        else if value.objectValue != nil { answers = [value] }
        else { return [] }
        // Desktop rejects the entire envelope when any answer lacks its required string fields.
        guard answers.allSatisfy({
            $0["questionItemId"].stringValue != nil && $0["question"].stringValue != nil && $0["answer"].stringValue != nil
        }) else { return [] }
        return answers.compactMap { $0["questionItemId"].stringValue }
    }
}
