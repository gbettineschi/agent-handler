import Foundation

/// Keeps item identity, question content and native answer envelopes. Tool results, reasoning and
/// rendered message bodies have no authority over questions. Retain a marker at their original path
/// so later nested patches can be ignored without losing array positions or stream revisions.
enum DesktopProjection {
    private static let itemFields: Set<String> = ["type", "id", "questions", "status", "content", "input"]

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
