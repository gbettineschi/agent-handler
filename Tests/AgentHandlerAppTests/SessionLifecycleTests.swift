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
    @Test func attentionAndUnknownAreNotReportedAsSuccess() {
        let now = Date()
        #expect(MenuBarState(sessions: [row(.needsInput), row(.running, turn: "b")], now: now).mode == .attention)
        #expect(MenuBarState(sessions: [row(.unknown)], now: now).mode == .unavailable)
        #expect(MenuBarState(sessions: [row(.failed)], now: now).mode == .failed)
        #expect(MenuBarState(sessions: [row(.running)], now: now).shouldAnimate(reduceMotion: true) == false)
        #expect(MenuBarState(sessions: [row(.running)], now: now).shouldAnimate(reduceMotion: false))
    }
}
