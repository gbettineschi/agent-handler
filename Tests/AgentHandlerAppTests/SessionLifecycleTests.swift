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
        let now = start.addingTimeInterval(100)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: start)
        lifecycle.observe([row(.completed)], now: start.addingTimeInterval(10))
        lifecycle.observe([row(.completed)], now: start.addingTimeInterval(100))
        let visible = lifecycle.visible([row(.completed)], now: now)
        #expect(visible.first?.recentUntil == start.addingTimeInterval(310))
        #expect(MenuBarState(sessions: visible, now: start.addingTimeInterval(309)).count == 1)
        #expect(MenuBarState(sessions: visible, now: start.addingTimeInterval(310)).count == 0)
        let reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        #expect(reopened.visible([row(.completed)], now: now).first?.recentUntil == start.addingTimeInterval(310))
    }
    @Test func oldCompletionAtLaunchIsNotReplayedAsRecent() {
        var lifecycle = SessionLifecycle()
        let now = Date()
        lifecycle.observe([row(.completed)], now: now)
        #expect(lifecycle.visible([row(.completed)], now: now).count == 1)
        #expect(MenuBarState(sessions: lifecycle.visible([row(.completed)], now: now), now: now).count == 0)
    }
    @Test func dismissedFinishStaysHiddenUntilWorkResumesEvenOnSameTurn() throws {
        var lifecycle = SessionLifecycle()
        let now = Date()
        lifecycle.observe([row(.completed)], now: now)
        lifecycle.dismiss(row(.completed))
        var reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        #expect(reopened.visible([row(.completed)], now: now).isEmpty)
        // A lost connection is never silently hidden as a completed session.
        #expect(reopened.visible([row(.unknown)], now: now).count == 1)
        reopened.observe([row(.running)], now: now)
        #expect(reopened.visible([row(.running)], now: now).count == 1)
        #expect(MenuBarState(sessions: reopened.visible([row(.running)], now: now), now: now).mode == .working)
        reopened.observe([row(.completed)], now: now)
        #expect(reopened.visible([row(.completed)], now: now).first?.recentUntil != nil)
    }
    @Test func newTurnReturnsAndActiveSessionsCannotBeDismissed() {
        var lifecycle = SessionLifecycle()
        let now = Date()
        lifecycle.observe([row(.completed)], now: now)
        lifecycle.dismiss(row(.completed))
        lifecycle.observe([row(.running, turn: "b")], now: now)
        lifecycle.dismiss(row(.running, turn: "b"))
        #expect(lifecycle.visible([row(.running, turn: "b")], now: now).count == 1)
        #expect(lifecycle.visible([row(.running, turn: "b")], now: now).first?.recentUntil == nil)
    }
    @Test func discoveryBaselineSeparatesLaunchHistoryFromNewFinishedChats() {
        var lifecycle = SessionLifecycle()
        let now = Date(timeIntervalSince1970: 1_000)
        lifecycle.establishBaseline(conversations: ["thread"])
        let newScope = RequestScope(installation: "desktop", conversation: "new-chat")
        let fresh = SessionSummary(id: newScope, title: "New chat", status: .completed, request: nil, turnID: "short")
        lifecycle.observe([row(.completed), fresh], now: now)
        #expect(lifecycle.visible([row(.completed)], now: now).first?.recentUntil == nil)
        #expect(lifecycle.visible([fresh], now: now).first?.recentUntil == now.addingTimeInterval(300))
    }
    @Test func restartDoesNotRefreshOfflineCompletionCountdown() throws {
        var lifecycle = SessionLifecycle()
        let now = Date(timeIntervalSince1970: 1_000)
        lifecycle.observe([row(.running)], now: now)
        var reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        reopened.establishBaseline(conversations: ["thread"])
        reopened.observe([row(.completed, turn: "b")], now: now.addingTimeInterval(500))
        #expect(reopened.visible([row(.completed, turn: "b")], now: now).first?.recentUntil == nil)
    }
    @Test func undoRestoresOnlyTheDismissedTurnWithoutExtendingItsCountdown() {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: now)
        lifecycle.observe([row(.completed)], now: now.addingTimeInterval(10))
        lifecycle.dismiss(row(.completed))
        #expect(lifecycle.visible([row(.completed)], now: now).isEmpty)
        let restored = lifecycle.restoreDismissed(row(.completed), now: now)
        #expect(restored)
        #expect(lifecycle.visible([row(.completed)], now: now).first?.recentUntil == now.addingTimeInterval(310))
        let restoredAgain = lifecycle.restoreDismissed(row(.completed), now: now)
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
        let restoredAgain = lifecycle.restoreDismissed(row(.completed), now: now)
        #expect(!restoredAgain)
        #expect(lifecycle.visible([row(.completed, turn: "b")], now: now).isEmpty)
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

    @Test func expiredFinishesDisappearAndResumeReturns() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: now)
        lifecycle.observe([row(.completed)], now: now.addingTimeInterval(10))
        // The finished time is durable and repeated observations cannot extend it.
        lifecycle.observe([row(.completed)], now: now.addingTimeInterval(310))
        #expect(lifecycle.visible([row(.completed)], now: now.addingTimeInterval(400)).isEmpty)
        var reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        reopened.observe([row(.completed)], now: now.addingTimeInterval(400))
        #expect(reopened.visible([row(.completed)], now: now.addingTimeInterval(400)).isEmpty)
        reopened.observe([row(.running)], now: now.addingTimeInterval(401))
        #expect(reopened.visible([row(.running)], now: now.addingTimeInterval(400)).count == 1)
        #expect(reopened.visible([row(.unknown)], now: now.addingTimeInterval(400)).count == 1)
    }

    @Test(arguments: [ActivityStatus.completed, .failed, .cancelled])
    func terminalRowsExpireAtTheExactDeadline(status: ActivityStatus) {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: now)
        lifecycle.observe([row(status)], now: now.addingTimeInterval(10))
        #expect(lifecycle.visible([row(status)], now: now.addingTimeInterval(309)).count == 1)
        #expect(lifecycle.visible([row(status)], now: now.addingTimeInterval(310)).isEmpty)
        lifecycle.dismiss(row(status))
        #expect(lifecycle.hidden([row(status)], now: now.addingTimeInterval(310)).isEmpty)
        let restored = lifecycle.restoreDismissed(row(status), now: now.addingTimeInterval(310))
        #expect(!restored)
    }
    @Test func launchHistoryExpiresWithoutBeingAnnouncedAsANewFinish() {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        let initial = lifecycle.observe([row(.completed)], now: now)
        #expect(initial.isEmpty)
        #expect(lifecycle.visible([row(.completed)], now: now.addingTimeInterval(299)).count == 1)
        #expect(lifecycle.visible([row(.completed)], now: now.addingTimeInterval(300)).isEmpty)
    }
    @Test func finishEventsDoNotRepeatOnTicksOrRestart() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: now)
        let first = lifecycle.observe([row(.completed)], now: now.addingTimeInterval(1))
        #expect(first.count == 1)
        let tick = lifecycle.observe([row(.completed)], now: now.addingTimeInterval(2))
        #expect(tick.isEmpty)
        var reopened = try JSONDecoder().decode(SessionLifecycle.self, from: JSONEncoder().encode(lifecycle))
        let restart = reopened.observe([row(.completed)], now: now.addingTimeInterval(3))
        #expect(restart.isEmpty)
        reopened.observe([row(.running)], now: now.addingTimeInterval(4))
        let next = reopened.observe([row(.completed)], now: now.addingTimeInterval(5))
        #expect(next.count == 1)
    }
    @Test func legacyDeadlineMigrationUsesTheOriginalFinishedTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        lifecycle.observe([row(.running)], now: now)
        lifecycle.observe([row(.completed)], now: now.addingTimeInterval(1))
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lifecycle)) as! [String: Any]
        var records = object["records"] as! [[String: Any]]
        for index in records.indices { records[index].removeValue(forKey: "expiresAt") }
        object["records"] = records
        var migrated = try JSONDecoder().decode(SessionLifecycle.self, from: JSONSerialization.data(withJSONObject: object))
        migrated.observe([row(.completed)], now: now.addingTimeInterval(400))
        #expect(migrated.visible([row(.completed)], now: now.addingTimeInterval(400)).isEmpty)
    }

}
