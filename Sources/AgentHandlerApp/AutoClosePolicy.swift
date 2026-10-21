import AgentHandlerCore

/// Window lifetime only; never changes provider or delivery state.
struct AutoClosePolicy {
    private var automatic = false
    private var claudeWaits: Set<RequestScope> = []
    private var finishes: Set<FinishedSessionID> = []

    mutating func openedAutomatically(for target: AutoOpenTarget, sessions: [SessionSummary]) {
        openedManually()
        automatic = true
        retainClaudeWaits(sessions)
        include(target)
    }
    mutating func include(_ target: AutoOpenTarget) {
        guard automatic, case .finished(let newlyFinished) = target else { return }
        finishes.formUnion(newlyFinished)
    }
    mutating func openedManually() {
        automatic = false; claudeWaits.removeAll(); finishes.removeAll()
    }
    mutating func update(requests: [RequestView], sessions: [SessionSummary], canClose: Bool = true) -> Bool {
        guard automatic else { return false }
        retainClaudeWaits(sessions)
        // Missing/unknown audit data cannot prove a permission wait ended.
        claudeWaits = claudeWaits.filter { scope in
            guard let session = sessions.first(where: { $0.id == scope }) else { return true }
            return session.status == .needsInput || session.status == .unknown
        }
        finishes = finishes.filter { finish in
            sessions.contains { $0.id == finish.scope &&
                ($0.status == .unknown || ($0.turnID == finish.turn && $0.isFinished)) }
        }
        // The controller retains unavailable/uncertain requests. Only accepted
        // or authoritatively closed requests leave its needs-attention list.
        guard canClose, !requests.contains(where: \.needsAttention), claudeWaits.isEmpty, finishes.isEmpty else { return false }
        openedManually()
        return true
    }
    private mutating func retainClaudeWaits(_ sessions: [SessionSummary]) {
        claudeWaits.formUnion(sessions.filter { $0.isClaude && $0.status == .needsInput }.map(\.id))
    }
}
