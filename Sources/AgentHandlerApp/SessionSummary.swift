import Foundation
import AgentHandlerCore

struct SessionSummary: Identifiable {
    let id: RequestScope
    let title: String
    let status: ActivityStatus
    let request: RequestView?
    var turnID: String? = nil
    var recentUntil: Date? = nil
    var expiresAt: Date? = nil
    var activityDetail: ActivityDetail? = nil
    var sourceLabel: String { isClaude ? "Claude" : "Codex" }
    var isFinished: Bool { [.completed, .failed, .cancelled].contains(status) && request == nil }
    func remaining(at now: Date) -> String? {
        guard let deadline = expiresAt ?? recentUntil, deadline > now else { return nil }
        let seconds = min(300, Int(ceil(deadline.timeIntervalSince(now))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    var isClaude: Bool { id.installation.hasPrefix("claude-local-audit:") }

    static func rows(activities: [ActivityView], requests: [RequestView], titles: [String: String], recentIDs: [String]) -> [Self] {
        func sessionScope(_ scope: RequestScope) -> RequestScope {
            guard scope.installation.hasSuffix(":approvals") else { return scope }
            return .init(installation: String(scope.installation.dropLast(":approvals".count)), conversation: scope.conversation)
        }
        let activityByID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let requestsByID = Dictionary(grouping: requests.filter(\.needsAttention), by: { sessionScope($0.id.scope) })
        let scopes = Set(activityByID.keys).union(requestsByID.keys)
        let order = Dictionary(recentIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return scopes.map { scope in
            let request = preferredRequest(requestsByID[scope] ?? [])
            let status: ActivityStatus
            if let request {
                status = [.pending, .sending].contains(request.state) ? .needsInput : .unknown
            } else { status = activityByID[scope]?.status ?? .unknown }
            return Self(id: scope, title: titles[scope.conversation] ?? (scope.installation.hasPrefix("claude-local-audit:") ? "Claude · \(scope.conversation.suffix(8))" : "Desktop session"),
                        status: status, request: request, turnID: activityByID[scope]?.turnID ?? request?.id.turn,
                        activityDetail: status == .running ? activityByID[scope]?.detail : nil)
        }.sorted {
            let lhs = order[$0.id.conversation] ?? Int.max, rhs = order[$1.id.conversation] ?? Int.max
            return lhs == rhs ? ($0.id.installation, $0.id.conversation) < ($1.id.installation, $1.id.conversation) : lhs < rhs
        }
    }
    static func preferredRequest(_ requests: [RequestView]) -> RequestView? {
        func rank(_ request: RequestView) -> Int {
            switch request.state {
            case .pending: 0
            case .sending: 1
            case .uncertain, .rejected: 2
            case .unavailable: 3
            case .accepted, .closed: 4
            }
        }
        return requests.filter(\.needsAttention).min { rank($0) < rank($1) }
    }
}
