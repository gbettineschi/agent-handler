import Testing
import AgentHandlerCore
@testable import AgentHandlerApp

struct ApprovalReviewTests {
    private func request(persistent: Bool = true, title: String = "Raw prompt") -> AttentionRequest {
        .init(key: .init(scope: .init(installation: "test", conversation: "test"), turn: "turn", nativeID: .integer(1)),
              owner: "test", title: title, content: .approval(choices: [.init(id: "once", label: "Allow once"), .init(id: "saved", label: "Native exact label")]),
              approvalDetails: .init(subject: .command(command: "printf test", directory: "/tmp", reason: nil),
                persistentActions: persistent ? ["saved": .commandRule(prefix: ["printf", "test"])] : [:]))
    }
    @Test func persistentChoiceRequiresExplicitReviewAndKeepsItsExactDecisionID() {
        var review = ApprovalReview()
        #expect(review.select("saved", in: request(), state: .pending) == nil)
        #expect(review.choiceID == "saved")
        #expect(review.confirm(in: request(), state: .pending) == .decision("saved"))
        #expect(review.confirm(in: request(), state: .pending) == nil)
        #expect(review.select("once", in: request(), state: .pending) == .decision("once"))
    }
    @Test func reviewCannotSendAfterWithdrawalOrChangeAndCanBeDismissed() {
        for state in [RequestState.sending, .uncertain, .closed, .unavailable, .rejected] {
            var review = ApprovalReview()
            _ = review.select("saved", in: request(), state: .pending)
            #expect(review.confirm(in: request(), state: state) == nil)
            #expect(review.select("once", in: request(), state: state) == nil)
        }
        var review = ApprovalReview()
        _ = review.select("saved", in: request(), state: .pending)
        #expect(review.confirm(in: request(persistent: false), state: .pending) == nil)
        _ = review.select("saved", in: request(), state: .pending)
        #expect(review.confirm(in: request(title: "Replacement request"), state: .pending) == nil)
        #expect(review.select("unknown", in: request(), state: .pending) == nil)
        review.dismiss()
        #expect(review.choiceID == nil)
    }
}
