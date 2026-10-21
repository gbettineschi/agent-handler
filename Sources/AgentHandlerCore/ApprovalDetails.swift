import Foundation

/// Display-only fields copied from a validated native request, never parsed from
/// its prose. Raw source title, choices and source fingerprint remain authoritative.
public struct ApprovalDetails: Equatable, Codable, Sendable {
    public enum Subject: Equatable, Codable, Sendable {
        case command(command: String, directory: String, reason: String?)
        case access(message: String, targetLabel: String, target: String, notices: [String], technicalDetails: String)
    }
    public enum PersistentAction: Equatable, Codable, Sendable {
        case commandRule(prefix: [String])
        case savedPermission
    }
    public let subject: Subject
    public let persistentActions: [String: PersistentAction]
    public init(subject: Subject, persistentActions: [String: PersistentAction] = [:]) {
        self.subject = subject; self.persistentActions = persistentActions
    }
    func isValid(choiceIDs: Set<String>) -> Bool {
        guard Set(persistentActions.keys).isSubset(of: choiceIDs),
              let data = try? JSONEncoder().encode(self), data.count <= 32_768 else { return false }
        return persistentActions.values.allSatisfy {
            if case .commandRule(let prefix) = $0 {
                return !prefix.isEmpty && prefix.count <= 64 && prefix.allSatisfy { !$0.isEmpty }
                    && (try? JSONEncoder().encode(prefix).count).map { $0 <= 4096 } == true
            }
            return true
        }
    }
}
