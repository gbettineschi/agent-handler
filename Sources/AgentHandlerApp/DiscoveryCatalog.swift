import CodexDesktopAdapter
import AgentHandlerCore

/// Discovery provides candidate IDs, never response authority or activity state.
/// A failed catalog read must not turn existing subscriptions into an empty set.
struct DiscoveryCatalog {
    static func selection(pending: [String], explicit: [String], activities: [ActivityView], observed: Set<String>, sourceOnly: Set<String>, candidates: [String], unowned: Set<String> = []) -> [String] {
        let activityIDs = Set(activities.map { $0.id.conversation })
        let unresolved = activities.filter {
            // Only an explicit negative owner search releases ordinary former
            // activity. A socket/parser gap is not evidence that its owner left.
            if unowned.contains($0.id.conversation), $0.attention == .clear { return false }
            if [.running, .needsInput].contains($0.status) { return true }
            // Lost availability cannot turn an observed clear terminal state
            // into a permanently pinned active session.
            return $0.status == .unknown && ($0.isCurrent || $0.phase == .running || $0.attention != .clear)
        }.map { $0.id.conversation }
        let ordered = pending + sourceOnly.sorted() + explicit + unresolved + observed.subtracting(activityIDs).subtracting(unowned).sorted() + candidates + unowned.sorted()
        var selected: [String] = []
        for id in ordered where !selected.contains(id) && selected.count < 16 { selected.append(id) }
        return selected
    }
    private(set) var candidates: [ThreadCandidate] = []
    private(set) var diagnostic: String?
    var retryNeeded: Bool { diagnostic != nil }
    var warning: String? {
        guard retryNeeded else { return nil }
        return candidates.isEmpty ? "Connecting to Desktop… Retrying automatically." : "Refreshing conversations… Retrying automatically."
    }
    mutating func update(_ result: Result<[ThreadCandidate], Error>) {
        switch result {
        case .success(let values): candidates = values; diagnostic = nil
        case .failure(let error):
            diagnostic = (error as? ThreadDiscovery.Failure)?.description ?? "Unexpected conversation catalog error"
        }
    }
}
