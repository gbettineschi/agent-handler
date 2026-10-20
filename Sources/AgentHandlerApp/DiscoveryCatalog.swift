import CodexDesktopAdapter

/// Discovery provides candidate IDs, never response authority or activity state.
/// A failed catalog read must not turn existing subscriptions into an empty set.
struct DiscoveryCatalog {
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
