import Foundation

/// Content-free observations for troubleshooting. These never grant response authority.
public struct DesktopDiagnostics: Sendable {
    public enum Connection: String, Sendable {
        case stopped, connecting, connected, unavailable, timedOut, refused, unreadableData
    }
    public enum Issue: String, Sendable, Hashable {
        case awaitingOwner, ownerUnavailable, awaitingSnapshot, unsupportedVersion
        case invalidSnapshot, resynchronizing, capacityExceeded
        case questionsUnsupported, approvalsUnsupported, activityUnsupported
    }
    public let connection: Connection
    /// Counts can overlap: one conversation can have more than one unavailable capability.
    public let issues: [Issue: Int]

    func message(known: Int) -> String {
        let connectionMessage: String
        switch connection {
        case .stopped: connectionMessage = "Codex tracking is stopped."
        case .connecting: connectionMessage = "Connecting to Codex…"
        case .connected: connectionMessage = "Codex connected."
        case .unavailable: connectionMessage = "Can't connect to Codex. Retrying automatically; continue in Codex."
        case .timedOut: connectionMessage = "Codex connection timed out. Retrying automatically; continue in Codex."
        case .refused: connectionMessage = "Codex refused the companion connection. Retrying safely; continue in Codex."
        case .unreadableData: connectionMessage = "Codex sent unreadable or oversized data. Retrying safely; continue in Codex."
        }
        let descriptions: [(Issue, String)] = [
            (.awaitingOwner, "Looking for open Codex conversations"),
            (.ownerUnavailable, "No open Codex conversation found for these candidates"),
            (.awaitingSnapshot, "Waiting for Codex state"),
            (.unsupportedVersion, "Unsupported Codex stream version; an Agent Handler update may be needed"),
            (.invalidSnapshot, "Codex sent an unsupported state; continue in Codex"),
            (.resynchronizing, "Refreshing Codex state; answers are paused until recovery"),
            (.capacityExceeded, "Conversation exceeds the tracking limit; continue in Codex"),
            (.questionsUnsupported, "Conversation data isn't supported for questions; continue in Codex"),
            (.approvalsUnsupported, "Approval data isn't supported; review approvals in Codex"),
            (.activityUnsupported, "Activity status is unavailable")
        ]
        // Ordinary catalog candidates need not be open in Desktop. Keep them out
        // of the user-facing warning when another owned conversation works.
        let details = descriptions.compactMap { issue, description -> String? in
            guard let count = issues[issue], count > 0,
                  known == 0 || ![.awaitingOwner, .ownerUnavailable, .awaitingSnapshot].contains(issue) else { return nil }
            return "\(description) (\(count))."
        }
        return ([connectionMessage] + details).joined(separator: "\n")
    }
}
