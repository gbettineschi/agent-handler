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
    var humanInputID: String? = nil
    var needsSourceApproval = false
    /// A positively observed native wait survives an observation gap. Presentation only.
    var hasUnresolvedSourceInput = false
    var hasObservedSourceWait: Bool {
        needsSourceApproval || hasUnresolvedSourceInput || (isClaude && status == .needsInput && request == nil)
    }
    var hasUnresolvedInput: Bool { request != nil || hasObservedSourceWait || status == .needsInput }
    var sourceLabel: String { isClaude ? "Claude" : "Codex" }
    var isFinished: Bool { [.completed, .failed, .cancelled].contains(status) && request == nil }
    var isClaude: Bool { id.installation.hasPrefix("claude-local-audit:") }

    static func rows(activities: [ActivityView], requests: [RequestView], titles: [String: String], recentIDs: [String],
                     observedScopes: Set<RequestScope> = [], sourceApprovalScopes: Set<RequestScope> = []) -> [Self] {
        func sessionScope(_ scope: RequestScope) -> RequestScope {
            guard scope.installation.hasSuffix(":approvals") else { return scope }
            return .init(installation: String(scope.installation.dropLast(":approvals".count)), conversation: scope.conversation)
        }
        let activityByID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let requestsByID = Dictionary(grouping: requests.filter(\.needsAttention), by: { sessionScope($0.id.scope) })
        let scopes = Set(activityByID.keys).union(requestsByID.keys).union(observedScopes).union(sourceApprovalScopes)
        let order = Dictionary(recentIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return scopes.map { scope in
            let request = preferredRequest(requestsByID[scope] ?? [])
            let sourceApproval = sourceApprovalScopes.contains(scope)
            let status: ActivityStatus
            if sourceApproval { status = .needsInput }
            else if let request {
                status = [.pending, .sending].contains(request.state) ? .needsInput : .unknown
            } else { status = activityByID[scope]?.status ?? .unknown }
            return Self(id: scope, title: titles[scope.conversation] ?? (scope.installation.hasPrefix("claude-local-audit:") ? "Claude · \(scope.conversation.suffix(8))" : "Desktop session"),
                        status: status, request: request, turnID: activityByID[scope]?.turnID ?? request?.id.turn,
                        activityDetail: status == .running ? activityByID[scope]?.detail : nil,
                        humanInputID: activityByID[scope]?.isCurrent == true ? activityByID[scope]?.humanInputID : nil,
                        needsSourceApproval: sourceApproval,
                        hasUnresolvedSourceInput: scope.installation.hasPrefix("claude-local-audit:") && request == nil && activityByID[scope]?.attention == .required)
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
