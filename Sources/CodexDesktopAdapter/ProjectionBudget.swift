import Foundation

/// Conservative accounting for the retained JSON tree, not a measurement of process RSS.
/// Walks values without serializing or allocating a second copy of the conversation.
enum ProjectionBudget {
    static let perConversation = 8 * 1024 * 1024
    static let total = 64 * 1024 * 1024
    static func cost(_ value: JSONValue, available: Int) -> Int? {
        var remaining = min(available, perConversation)
        let initial = remaining
        func consume(_ amount: Int) -> Bool {
            guard amount <= remaining else { return false }; remaining -= amount; return true
        }
        func visit(_ value: JSONValue, depth: Int) -> Bool {
            guard depth < 128, consume(32) else { return false }
            switch value {
            case .string(let text): return consume(text.utf8.count)
            case .array(let values):
                for child in values { guard visit(child, depth: depth + 1) else { return false } }
            case .object(let values):
                for (key, child) in values {
                    guard consume(64 + key.utf8.count), visit(child, depth: depth + 1) else { return false }
                }
            default: break
            }
            return true
        }
        return visit(value, depth: 0) ? initial - remaining : nil
    }
}
