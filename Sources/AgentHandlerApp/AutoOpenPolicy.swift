import Foundation
import AgentHandlerCore

struct AutoOpenSettings: Codable, Equatable {
    var blocking = true
    var finished = false
    var nonBlocking = false
    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: "autoOpen.v1"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "autoOpen.v1") }
    }
}
struct FinishedSessionID: Hashable {
    let scope: RequestScope
    let turn: String?
}
enum AutoOpenTarget: Equatable { case request(RequestKey), sessions, finished(Set<FinishedSessionID>) }
struct AutoOpenPolicy {
    private var seenRequests: Set<RequestKey> = []
    private var requestHistory: [RequestKey] = []
    private var claudeState: [RequestScope: SessionSummary] = [:]

    mutating func update(requests: [RequestView], sessions: [SessionSummary], newlyFinished: [SessionSummary],
                         settings: AutoOpenSettings, enabled: Bool = true) -> AutoOpenTarget? {
        let pending = requests.filter { $0.state == .pending }
        let fresh = pending.filter { !seenRequests.contains($0.id) }
        for view in fresh { seenRequests.insert(view.id); requestHistory.append(view.id) }
        requestHistory = Array(requestHistory.suffix(512))
        seenRequests = seenRequests.intersection(Set(requests.map(\.id))).union(requestHistory)

        // Claude's read-only audit reports actual permission waits. Unknown gaps
        // do not rearm them; an observed running state or a new turn does.
        var newClaudeWait = false
        for session in sessions where session.isClaude && session.status != .unknown {
            let old = claudeState[session.id]
            if session.status == .needsInput, session.request == nil,
               old?.status != .needsInput || old?.turnID != session.turnID { newClaudeWait = true }
            claudeState[session.id] = session
        }
        if claudeState.count > 256 {
            let current = Set(sessions.map(\.id))
            claudeState = claudeState.filter { current.contains($0.key) }
        }
        guard enabled else { return nil }
        if settings.blocking {
            if let view = fresh.first(where: { if case .approval = $0.request.content { return true }; return false }) {
                return .request(view.id)
            }
            if newClaudeWait { return .sessions }
        }
        if settings.nonBlocking, let view = fresh.first(where: {
            guard $0.id.scope.installation.hasPrefix("codex-desktop:") else { return false }
            if case .question = $0.request.content { return true }; return false
        }) { return .request(view.id) }
        if settings.finished {
            let finished = Set(newlyFinished.filter(\.isFinished).map { FinishedSessionID(scope: $0.id, turn: $0.turnID) })
            if !finished.isEmpty { return .finished(finished) }
        }
        return nil
    }
}
