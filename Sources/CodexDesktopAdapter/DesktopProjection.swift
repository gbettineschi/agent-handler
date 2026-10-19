import Foundation

/// Keeps item identity, question content and native answer envelopes. Tool results, reasoning and
/// rendered message bodies have no authority over questions. Retain a marker at their original path
/// so later nested patches can be ignored without losing array positions or stream revisions.
enum DesktopProjection {
    static func decodeFrame(_ data: Data) throws -> JSONValue {
        try JSONValue.parseDesktopFrame(data)
    }
    private static let itemFields: Set<String> = ["type", "id", "questions", "status", "content", "input"]
    private static let turnFields: Set<String> = ["turnId", "status", "items", "itemsPagination", "params"]

    /// The same projection as compact(), applied before unused values become an allocated tree.
    /// Everything outside the recognized snapshot path, especially approvals and patch values,
    /// retains the normal strict decoder and its node allowance.
    enum Context {
        case raw, frame, parameters, change, state, turns, turnHistory, history, entities, turn, settings, items, item, discarded
        func member(_ key: String) -> Self {
            switch self {
            case .frame: return key == "params" ? .parameters : .raw
            case .parameters: return key == "change" ? .change : .raw
            case .change: return key == "conversationState" ? .state : .raw
            case .state:
                return key == "turns" ? .turns : key == "turnHistory" ? .turnHistory : .raw
            case .turnHistory: return key == "history" ? .history : .raw
            case .history: return key == "entitiesByKey" ? .entities : .raw
            case .entities: return .turn
            case .turn:
                guard turnFields.contains(key) else { return .discarded }
                return key == "items" ? .items : key == "params" ? .settings : .raw
            case .settings: return ["approvalsReviewer", "approvalPolicy", "sandboxPolicy"].contains(key) ? .raw : .discarded
            case .item: return itemFields.contains(key) ? .raw : .discarded
            default: return .raw
            }
        }
        var element: Self { self == .turns ? .turn : self == .items ? .item : .raw }
    }

    static func compact(_ state: inout JSONValue) {
        state.projectMember("turns") { turns in
            guard case .array(var values) = turns else { return }
            turns = .null
            for index in values.indices { compactTurn(&values[index]) }
            turns = .array(values)
        }
        state.projectMember("turnHistory") { history in
            history.projectMember("history") { storage in
                storage.projectMember("entitiesByKey") { entities in
                    guard case .object(var values) = entities else { return }
                    entities = .null
                    for key in values.keys { compactTurn(&values[key]!) }
                    entities = .object(values)
                }
            }
        }
    }

    private static func compactTurn(_ turn: inout JSONValue) {
        guard case .object(var fields) = turn else { return }
        turn = .null
        for key in fields.keys where !turnFields.contains(key) { fields[key] = .discarded }
        turn = .object(fields)
        turn.projectMember("params") { params in
            guard case .object(var fields) = params else { return }
            for key in fields.keys where !["approvalsReviewer", "approvalPolicy", "sandboxPolicy"].contains(key) { fields[key] = .discarded }
            params = .object(fields)
        }
        turn.projectMember("items") { items in
            guard case .array(var values) = items else { return }
            items = .null
            for index in values.indices {
                guard case .object(var fields) = values[index] else { continue }
                values[index] = .null
                for key in fields.keys where !itemFields.contains(key) { fields[key] = .discarded }
                values[index] = .object(fields)
            }
            items = .array(values)
        }
    }
}

private extension JSONValue {
    mutating func projectMember(_ name: String, _ transform: (inout JSONValue) -> Void) {
        guard case .object(var fields) = self, fields[name] != nil else { return }
        self = .null
        transform(&fields[name]!)
        self = .object(fields)
    }
}
