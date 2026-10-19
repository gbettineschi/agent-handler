import Foundation
import AgentHandlerCore

/// Ephemeral UI state. A draft is never a delivery attempt and is never persisted.
struct QuestionDraft {
    private(set) var text = ""
    private(set) var choice: String?

    mutating func select(_ id: String) { choice = id; text = "" }
    mutating func write(_ value: String) {
        text = value
        if !value.isEmpty { choice = nil }
    }
    func answer(options: [ResponseOption], allowsText: Bool) -> UserAnswer? {
        if let choice, options.contains(where: { $0.id == choice }) { return .option(choice) }
        guard allowsText, text.utf8.count <= 16_384,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .text(text)
    }
}
