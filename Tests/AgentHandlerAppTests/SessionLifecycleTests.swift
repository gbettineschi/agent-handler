import Foundation
import Testing
import AgentHandlerCore
@testable import AgentHandlerApp

struct SessionLifecycleTests {
    let scope = RequestScope(installation: "desktop", conversation: "thread")
    func row(_ status: ActivityStatus, turn: String = "a") -> SessionSummary {
        .init(id: scope, title: "Actual chat title", status: status, request: nil, turnID: turn)
    }
    @Test func countdownStartsOnObservedFinishAndDoesNotResetOnRepeatedSnapshots() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: start)
        lifecycle.observe([row(.completed)], now: start.addingTimeInterval(10))
        lifecycle.observe([row(.completed)], now: start.addingTimeInterval(100))
        let visible = lifecycle.visible([row(.completed)])
        #expect(visible.first?.recentUntil == start.addingTimeInterval(310))
        #expect(MenuBarState(sessions: visible, now: start.addingTimeInterval(309)).count == 1)
        #expect(MenuBarState(sessions: visible, now: start.addingTimeInterval(310)).count == 0)
        let reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        #expect(reopened.visible([row(.completed)]).first?.recentUntil == start.addingTimeInterval(310))
    }
    @Test func oldCompletionAtLaunchIsNotReplayedAsRecent() {
        var lifecycle = SessionLifecycle()
        let now = Date()
        lifecycle.observe([row(.completed)], now: now)
        #expect(lifecycle.visible([row(.completed)]).count == 1)
        #expect(MenuBarState(sessions: lifecycle.visible([row(.completed)]), now: now).count == 0)
    }
    @Test func dismissedFinishStaysHiddenUntilWorkResumesEvenOnSameTurn() throws {
        var lifecycle = SessionLifecycle()
        let now = Date()
        lifecycle.observe([row(.completed)], now: now)
        lifecycle.dismiss(row(.completed))
        var reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        #expect(reopened.visible([row(.completed)]).isEmpty)
        // A lost connection is never silently hidden as a completed session.
        #expect(reopened.visible([row(.unknown)]).count == 1)
        reopened.observe([row(.running)], now: now)
        #expect(reopened.visible([row(.running)]).count == 1)
        #expect(MenuBarState(sessions: reopened.visible([row(.running)]), now: now).mode == .working)
        reopened.observe([row(.completed)], now: now)
        #expect(reopened.visible([row(.completed)]).first?.recentUntil != nil)
    }
    @Test func newTurnReturnsAndActiveSessionsCannotBeDismissed() {
        var lifecycle = SessionLifecycle()
        let now = Date()
        lifecycle.observe([row(.completed)], now: now)
        lifecycle.dismiss(row(.completed))
        lifecycle.observe([row(.running, turn: "b")], now: now)
        lifecycle.dismiss(row(.running, turn: "b"))
        #expect(lifecycle.visible([row(.running, turn: "b")]).count == 1)
        #expect(lifecycle.visible([row(.running, turn: "b")]).first?.recentUntil == nil)
    }
    @Test func discoveryBaselineSeparatesLaunchHistoryFromNewFinishedChats() {
        var lifecycle = SessionLifecycle()
        let now = Date(timeIntervalSince1970: 1_000)
        lifecycle.establishBaseline(conversations: ["thread"])
        let newScope = RequestScope(installation: "desktop", conversation: "new-chat")
        let fresh = SessionSummary(id: newScope, title: "New chat", status: .completed, request: nil, turnID: "short")
        lifecycle.observe([row(.completed), fresh], now: now)
        #expect(lifecycle.visible([row(.completed)]).first?.recentUntil == nil)
        #expect(lifecycle.visible([fresh]).first?.recentUntil == now.addingTimeInterval(300))
    }
    @Test func restartDoesNotRefreshOfflineCompletionCountdown() throws {
        var lifecycle = SessionLifecycle()
        let now = Date(timeIntervalSince1970: 1_000)
        lifecycle.observe([row(.running)], now: now)
        var reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        reopened.establishBaseline(conversations: ["thread"])
        reopened.observe([row(.completed, turn: "b")], now: now.addingTimeInterval(500))
        #expect(reopened.visible([row(.completed, turn: "b")]).first?.recentUntil == nil)
    }
    @Test func undoRestoresOnlyTheDismissedTurnWithoutExtendingItsCountdown() {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: now)
        lifecycle.observe([row(.completed)], now: now.addingTimeInterval(10))
        lifecycle.dismiss(row(.completed))
        #expect(lifecycle.visible([row(.completed)]).isEmpty)
        let restored = lifecycle.restoreDismissed(row(.completed))
        #expect(restored)
        #expect(lifecycle.visible([row(.completed)]).first?.recentUntil == now.addingTimeInterval(310))
        let restoredAgain = lifecycle.restoreDismissed(row(.completed))
        #expect(!restoredAgain)
    }
    @Test func undoOldTurnCannotUnhideANewerDismissedFinish() {
        let now = Date()
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.completed)], now: now)
        lifecycle.dismiss(row(.completed))
        lifecycle.observe([row(.running, turn: "b")], now: now)
        lifecycle.observe([row(.completed, turn: "b")], now: now)
        lifecycle.dismiss(row(.completed, turn: "b"))
        let restoredAgain = lifecycle.restoreDismissed(row(.completed))
        #expect(!restoredAgain)
        #expect(lifecycle.visible([row(.completed, turn: "b")]).isEmpty)
    }
    @Test func undoOfferExpiresAndWithdrawsWhenWorkRestarts() {
        let now = Date(timeIntervalSince1970: 1_000)
        let offer = SessionDismissal(session: row(.completed), now: now)
        #expect(offer.canUndo(in: [row(.completed)], now: now.addingTimeInterval(9)))
        #expect(!offer.canUndo(in: [row(.completed)], now: now.addingTimeInterval(10)))
        #expect(!offer.canUndo(in: [row(.running)], now: now))
        #expect(!offer.canUndo(in: [row(.completed, turn: "b")], now: now))
        #expect(!offer.canUndo(in: [row(.unknown)], now: now))
    }
    @Test @MainActor func resettingDemoRestoresDismissedExamplesAndClearsUndo() async throws {
        let model = try AppModel(demo: true)
        await model.loadDemo(.empty)
        model.updateSessionPresentation()
        let candidate = model.sessions.first { $0.isFinished }
        let finished = try #require(candidate)
        model.dismissSession(finished)
        #expect(model.sessions.count == 2)
        #expect(model.dismissal != nil)
        await model.loadDemo(.empty)
        model.updateSessionPresentation()
        #expect(model.sessions.count == 3)
        #expect(model.dismissal == nil)
    }
    @Test func hiddenSessionsAreRecoverableButDoNotIncludeActiveOrUnknownState() {
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.completed)], now: Date())
        lifecycle.dismiss(row(.completed))
        #expect(lifecycle.hidden([row(.completed)]).map(\.title) == ["Actual chat title"])
        #expect(lifecycle.hidden([row(.running), row(.unknown)]).isEmpty)
        #expect(lifecycle.hidden([row(.completed, turn: "b")]).isEmpty)
    }
    @Test func attentionAndUnknownAreNotReportedAsSuccess() {
        let now = Date()
        #expect(MenuBarState(sessions: [row(.needsInput), row(.running, turn: "b")], now: now).mode == .attention)
        #expect(MenuBarState(sessions: [row(.unknown)], now: now).mode == .unavailable)
        #expect(MenuBarState(sessions: [row(.failed)], now: now).mode == .failed)
        #expect(MenuBarState(sessions: [row(.running)], now: now).shouldAnimate(reduceMotion: true) == false)
        #expect(MenuBarState(sessions: [row(.running)], now: now).shouldAnimate(reduceMotion: false))
    }
    @Test func sourceLabelsIdentifyTheProvider() {
        #expect(row(.running).sourceLabel == "Codex")
        let claude = SessionSummary(id: .init(installation: "claude-local-audit:desktop", conversation: "c"), title: "Claude chat", status: .running, request: nil)
        #expect(claude.sourceLabel == "Claude")
    }

}
