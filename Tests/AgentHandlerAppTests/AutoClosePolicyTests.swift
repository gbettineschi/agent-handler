import Foundation
import Testing
@testable import AgentHandlerCore
@testable import AgentHandlerApp

struct AutoClosePolicyTests {
    private let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "chat")
    private func request(_ id: String = "first", state: RequestState = .pending) -> RequestView {
        .init(request: .init(key: .init(scope: scope, turn: "turn", nativeID: .string(id)), owner: "owner", title: "Question",
            content: .question(options: [], allowsText: true)), state: state)
    }
    @Test func lastResolvedRequestClosesAnAutomaticOpeningOnlyOnce() {
        var policy = AutoClosePolicy()
        let first = request()
        policy.openedAutomatically(for: .request(first.id), sessions: [])
        #expect(!{ policy.update(requests: [first], sessions: []) }())
        #expect({ policy.update(requests: [], sessions: []) }())
        #expect(!{ policy.update(requests: [], sessions: []) }())
    }
    @Test func unresolvedSiblingsAndNewRequestsKeepThePanelOpen() {
        var policy = AutoClosePolicy()
        let first = request(), second = request("second"), third = request("third")
        policy.openedAutomatically(for: .request(first.id), sessions: [])
        #expect(!{ policy.update(requests: [second], sessions: []) }())
        #expect(!{ policy.update(requests: [third], sessions: []) }())
        #expect({ policy.update(requests: [], sessions: []) }())
    }
    @Test func sendingUncertaintyAndDisconnectionAreNotResolution() {
        for state in [RequestState.sending, .uncertain, .unavailable, .rejected] {
            var policy = AutoClosePolicy()
            let first = request()
            policy.openedAutomatically(for: .request(first.id), sessions: [])
            #expect(!{ policy.update(requests: [request(state: state)], sessions: []) }())
            #expect({ policy.update(requests: [request(state: .closed)], sessions: []) }())
        }
    }
    @Test func manualOpeningOrTakeoverNeverClosesWhenRequestsResolve() {
        var policy = AutoClosePolicy()
        #expect(!{ policy.update(requests: [], sessions: []) }())
        let first = request()
        policy.openedAutomatically(for: .request(first.id), sessions: [])
        policy.openedManually()
        #expect(!{ policy.update(requests: [], sessions: []) }())
        policy.openedAutomatically(for: .request(first.id), sessions: [])
        #expect({ policy.update(requests: [request(state: .accepted)], sessions: []) }())
    }
    @Test func readOnlyClaudeWaitNeedsPositiveRecoveryRatherThanMissingData() {
        var policy = AutoClosePolicy()
        func row(_ status: ActivityStatus) -> SessionSummary {
            .init(id: .init(installation: "claude-local-audit:fixture", conversation: "claude"), title: "Claude",
                status: status, request: nil, turnID: "turn")
        }
        policy.openedAutomatically(for: .sessions, sessions: [row(.needsInput)])
        #expect(!{ policy.update(requests: [], sessions: [row(.unknown)]) }())
        #expect(!{ policy.update(requests: [], sessions: []) }())
        #expect({ policy.update(requests: [], sessions: [row(.running)]) }())
    }
    @Test func finishedOpeningClosesWhenTheNotifiedRowsExpireOrAreDismissed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let active = SessionSummary(id: scope, title: "Session", status: .running, request: nil, turnID: "turn")
        let finished = SessionSummary(id: scope, title: "Session", status: .completed, request: nil, turnID: "turn")
        var lifecycle = SessionLifecycle(), policy = AutoClosePolicy()
        lifecycle.observe([active], now: now)
        lifecycle.observe([finished], now: now.addingTimeInterval(1))
        policy.openedAutomatically(for: .finished([.init(scope: scope, turn: "turn")]), sessions: lifecycle.visible([finished], now: now.addingTimeInterval(1)))
        #expect(!{ policy.update(requests: [], sessions: lifecycle.visible([finished], now: now.addingTimeInterval(300))) }())
        #expect({ policy.update(requests: [], sessions: lifecycle.visible([finished], now: now.addingTimeInterval(301))) }())
        policy.openedAutomatically(for: .finished([.init(scope: scope, turn: finished.turnID)]), sessions: [finished])
        lifecycle.dismiss(finished)
        #expect({ policy.update(requests: [], sessions: lifecycle.visible([finished], now: now.addingTimeInterval(2))) }())
    }
    @Test func unrelatedRecentFinishesDoNotKeepAnAnsweredQuestionOpen() {
        var policy = AutoClosePolicy()
        let first = request()
        let finished = SessionSummary(id: scope, title: "Session", status: .completed, request: nil, turnID: "earlier")
        policy.openedAutomatically(for: .request(first.id), sessions: [finished])
        #expect({ policy.update(requests: [], sessions: [finished]) }())
    }
    @Test func newInputDuringAFinishNoticeIsNotHiddenWhenTheFinishExpires() {
        var policy = AutoClosePolicy()
        let finished = SessionSummary(id: scope, title: "Session", status: .completed, request: nil, turnID: "earlier")
        policy.openedAutomatically(for: .finished([.init(scope: scope, turn: finished.turnID)]), sessions: [finished])
        #expect(!{ policy.update(requests: [request()], sessions: []) }())
        #expect({ policy.update(requests: [], sessions: []) }())
    }
    @Test func answeringAnExistingQuestionDoesNotEraseTheFinishThatOpenedThePanel() {
        var policy = AutoClosePolicy()
        let finished = SessionSummary(id: scope, title: "Session", status: .completed, request: nil, turnID: "earlier")
        policy.openedAutomatically(for: .finished([.init(scope: scope, turn: finished.turnID)]), sessions: [finished])
        #expect(!{ policy.update(requests: [], sessions: [finished]) }())
    }
    @Test func unrelatedFinishedRowsDoNotExtendTheNotifiedTurn() {
        var policy = AutoClosePolicy()
        let notified = SessionSummary(id: scope, title: "New finish", status: .completed, request: nil, turnID: "new")
        let old = SessionSummary(id: .init(installation: scope.installation, conversation: "old"), title: "Earlier finish",
            status: .completed, request: nil, turnID: "old")
        policy.openedAutomatically(for: .finished([.init(scope: scope, turn: "new")]), sessions: [old, notified])
        #expect({ policy.update(requests: [], sessions: [old]) }())
    }
    @Test func additionalFinishEventsExtendOnlyAnAutomaticOpening() {
        var policy = AutoClosePolicy()
        let next = SessionSummary(id: scope, title: "Next finish", status: .completed, request: nil, turnID: "new")
        let event = AutoOpenTarget.finished([.init(scope: scope, turn: "new")])
        policy.openedAutomatically(for: .request(request().id), sessions: [])
        policy.include(event)
        #expect(!{ policy.update(requests: [], sessions: [next]) }())
        #expect({ policy.update(requests: [], sessions: []) }())
        policy.openedManually(); policy.include(event)
        #expect(!{ policy.update(requests: [], sessions: []) }())
    }
    @Test func menuTrackingDefersClosingWithoutLosingNewWaitObservations() {
        var policy = AutoClosePolicy()
        func row(_ status: ActivityStatus) -> SessionSummary {
            .init(id: .init(installation: "claude-local-audit:fixture", conversation: "claude"), title: "Claude",
                status: status, request: nil, turnID: "turn")
        }
        policy.openedAutomatically(for: .request(request().id), sessions: [])
        #expect(!{ policy.update(requests: [request()], sessions: [row(.needsInput)], canClose: false) }())
        #expect(!{ policy.update(requests: [], sessions: [row(.unknown)]) }())
        #expect(!{ policy.update(requests: [], sessions: [row(.running)], canClose: false) }())
        #expect({ policy.update(requests: [], sessions: [row(.running)]) }())
    }
}
