import AgentHandlerCore

/// Read-only lifecycle facts from the same versioned owner state as requests.
/// Does not infer completion from item text, a missing request or a quiet connection.
enum DesktopActivity {
    enum Failure: Error { case unsupported }

    static func parse(state: JSONValue, threadID: String, owner: String, installation: String) throws
        -> (turnID: String, phase: ActivityPhase, attention: ActivityAttention) {
        if state["turnHistory"] != .null {
            guard state["turnHistory"]["kind"].stringValue == "canonical",
                  let islands = state["turnHistory"]["history"]["islands"].arrayValue,
                  islands.count == 1, islands[0]["newerBoundary"]["status"].stringValue == "exhausted",
                  (state["turns"].arrayValue ?? []).isEmpty else { throw Failure.unsupported }
        }
        let turns = try DesktopQuestions.turns(state)
        guard !turns.dropLast().contains(where: { $0["status"].stringValue == "inProgress" }),
              let turn = turns.last,
              let turnID = turn["turnId"].stringValue, !turnID.isEmpty, turnID.utf8.count <= 256 else { throw Failure.unsupported }
        let phase: ActivityPhase
        switch turn["status"].stringValue {
        case "inProgress": phase = .running
        case "completed": phase = .completed
        case "failed": phase = .failed
        case "interrupted": phase = .cancelled
        default: throw Failure.unsupported
        }
        if phase == .completed {
            guard ["unconfirmedTurnSubmissions", "queuedMessages"].allSatisfy({
                state[$0] == .null || state[$0].arrayValue?.isEmpty == true
            }), state["threadGoal"]["status"].stringValue != "active" else { throw Failure.unsupported }
        }
        let questions = try? DesktopQuestions.parse(state: state, threadID: threadID, owner: owner, installation: installation)
        let approvals = try? DesktopApprovals.pending(state: state, threadID: threadID, owner: owner, installation: installation)
        let attention: ActivityAttention
        if questions?.isEmpty == false || approvals?.isEmpty == false { attention = .required }
        else if questions != nil, approvals != nil, let requests = state["requests"].arrayValue,
                requests.allSatisfy({ $0.objectValue != nil && $0["method"].stringValue?.isEmpty == false && $0["completed"] == .bool(true) }) {
            attention = .clear
        } else { attention = .unknown }
        return (turnID, phase, attention)
    }
}
