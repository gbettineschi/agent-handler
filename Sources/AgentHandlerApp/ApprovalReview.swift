import AgentHandlerCore

/// Opening a persistent-choice review is local UI state, never a submission.
struct ApprovalReview {
    private(set) var choiceID: String?
    private var fingerprint: String?
    mutating func select(_ id: String, in request: AttentionRequest, state: RequestState) -> UserAnswer? {
        guard state == .pending, case .approval(let choices) = request.content,
              choices.contains(where: { $0.id == id }) else { return nil }
        if request.approvalDetails?.persistentActions[id] != nil {
            choiceID = id; fingerprint = request.fingerprint; return nil
        }
        dismiss()
        return .decision(id)
    }
    mutating func confirm(in request: AttentionRequest, state: RequestState) -> UserAnswer? {
        defer { dismiss() }
        guard state == .pending, let id = choiceID,
              fingerprint == request.fingerprint,
              request.approvalDetails?.persistentActions[id] != nil,
              case .approval(let choices) = request.content, choices.contains(where: { $0.id == id }) else { return nil }
        return .decision(id)
    }
    mutating func dismiss() { choiceID = nil; fingerprint = nil }
}
