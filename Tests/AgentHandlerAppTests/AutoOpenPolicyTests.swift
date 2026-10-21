import Foundation
import Testing
@testable import AgentHandlerCore
@testable import AgentHandlerApp

struct AutoOpenPolicyTests {
    let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "chat")
    func request(_ approval: Bool, id: String = "q", state: RequestState = .pending) -> RequestView {
        let request = AttentionRequest(key: .init(scope: scope, turn: "t", nativeID: .string(id)), owner: "owner", title: "Native request",
            content: approval ? .approval(choices: [.init(id: "yes", label: "Allow")]) : .question(options: [], allowsText: true))
        return .init(request: request, state: state)
    }
    @Test func blockingDefaultDoesNotTreatCodexAsyncQuestionsAsBlocking() {
        var policy = AutoOpenPolicy()
        let question = request(false), approval = request(true, id: "a")
        let quiet = policy.update(requests: [question], sessions: [], newlyFinished: [], settings: .init())
        #expect(quiet == nil)
        let opened = policy.update(requests: [question, approval], sessions: [], newlyFinished: [], settings: .init())
        #expect(opened == .request(approval.id))
        let repeatEvent = policy.update(requests: [question, approval], sessions: [], newlyFinished: [], settings: .init())
        #expect(repeatEvent == nil)
    }
    @Test func nonBlockingHasAnIndependentToggleAndDoesNotReplayAfterReconnect() {
        var policy = AutoOpenPolicy()
        let settings = AutoOpenSettings(blocking: false, finished: false, nonBlocking: true)
        let q = request(false)
        let first = policy.update(requests: [q], sessions: [], newlyFinished: [], settings: settings)
        #expect(first == .request(q.id))
        _ = policy.update(requests: [request(false, state: .unavailable)], sessions: [], newlyFinished: [], settings: settings)
        let reconnect = policy.update(requests: [q], sessions: [], newlyFinished: [], settings: settings)
        #expect(reconnect == nil)
        let next = request(false, id: "second")
        let newEvent = policy.update(requests: [next], sessions: [], newlyFinished: [], settings: settings)
        #expect(newEvent == .request(next.id))
    }
    @Test func finishedToggleOnlyAcceptsNewObservedFinishesAndPauseSuppressesOpening() {
        let ended = SessionSummary(id: scope, title: "Finished", status: .completed, request: nil, turnID: "t")
        var policy = AutoOpenPolicy()
        let settings = AutoOpenSettings(blocking: true, finished: true, nonBlocking: false)
        let unrelated = SessionSummary(id: .init(installation: scope.installation, conversation: "old"),
            title: "Earlier finish", status: .completed, request: nil, turnID: "old")
        let start = policy.update(requests: [], sessions: [ended], newlyFinished: [], settings: settings)
        #expect(start == nil)
        let newFinish = policy.update(requests: [], sessions: [unrelated, ended], newlyFinished: [ended], settings: settings)
        #expect(newFinish == .finished([.init(scope: scope, turn: "t")]))
        let paused = policy.update(requests: [request(true)], sessions: [], newlyFinished: [], settings: settings, enabled: false)
        #expect(paused == nil)
    }
    @Test func uncertaintyAndDisabledOptionsNeverOpenOrReplayWhenEnabledLater() {
        var policy = AutoOpenPolicy()
        let off = AutoOpenSettings(blocking: false, finished: false, nonBlocking: false)
        let disabled = policy.update(requests: [request(true)], sessions: [], newlyFinished: [], settings: off)
        #expect(disabled == nil)
        let toggled = policy.update(requests: [request(true)], sessions: [], newlyFinished: [], settings: .init())
        #expect(toggled == nil)
        let uncertain = policy.update(requests: [request(true, id: "u", state: .uncertain)], sessions: [], newlyFinished: [], settings: .init())
        #expect(uncertain == nil)
    }
    @Test func preferencesPersistIndependently() {
        let suite = "ah-auto-open-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AutoOpenSettings.load(from: defaults) == AutoOpenSettings())
        let value = AutoOpenSettings(blocking: false, finished: true, nonBlocking: true)
        value.save(to: defaults)
        #expect(AutoOpenSettings.load(from: defaults) == value)
    }
    @Test(arguments: [false, true]) func sourcePermissionWaitDoesNotReplayAcrossUnknownGaps(codex: Bool) {
        var policy = AutoOpenPolicy()
        func row(_ status: ActivityStatus) -> SessionSummary {
            .init(id: .init(installation: codex ? "codex-desktop:fixture" : "claude-local-audit:fixture", conversation: "c"), title: "Source", status: status, request: nil, turnID: "t", needsSourceApproval: codex && status == .needsInput)
        }
        let first = policy.update(requests: [], sessions: [row(.needsInput)], newlyFinished: [], settings: .init())
        #expect(first == .sessions)
        _ = policy.update(requests: [], sessions: [row(.unknown)], newlyFinished: [], settings: .init())
        let reconnect = policy.update(requests: [], sessions: [row(.needsInput)], newlyFinished: [], settings: .init())
        #expect(reconnect == nil)
        _ = policy.update(requests: [], sessions: [row(.running)], newlyFinished: [], settings: .init())
        let next = policy.update(requests: [], sessions: [row(.needsInput)], newlyFinished: [], settings: .init())
        #expect(next == .sessions)
    }
    @Test func activeRequestsBeyondTheHistoryBoundAreNotReplayed() {
        var policy = AutoOpenPolicy()
        let requests = (0..<600).map { request(true, id: "request-\($0)") }
        let first = policy.update(requests: requests, sessions: [], newlyFinished: [], settings: .init())
        #expect(first != nil)
        let next = policy.update(requests: requests, sessions: [], newlyFinished: [], settings: .init())
        #expect(next == nil)
    }
    @Test func aSourceOnlyRequestCanAppearBesideARetainedCard() {
        var policy = AutoOpenPolicy()
        let retained = request(true, state: .unavailable)
        var row = SessionSummary(id: scope, title: "Chat", status: .needsInput, request: retained, turnID: "t", needsSourceApproval: true)
        #expect(policy.update(requests: [retained], sessions: [row], newlyFinished: [], settings: .init()) == .sessions)
        #expect(policy.update(requests: [retained], sessions: [row], newlyFinished: [], settings: .init()) == nil)
        row.needsSourceApproval = false
        _ = policy.update(requests: [retained], sessions: [row], newlyFinished: [], settings: .init())
        row.needsSourceApproval = true
        #expect(policy.update(requests: [retained], sessions: [row], newlyFinished: [], settings: .init()) == .sessions)
    }

    @Test func unresolvedInputCannotExpireEvenAfterTheOldFinishDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        var lifecycle = SessionLifecycle()
        let ended = SessionSummary(id: scope, title: "Old finish", status: .completed, request: nil, turnID: "t")
        lifecycle.observe([ended], now: now)
        let unresolved = SessionSummary(id: scope, title: "Needs attention", status: .unknown,
                                       request: request(true, state: .uncertain), turnID: "t")
        #expect(lifecycle.visible([unresolved], now: now.addingTimeInterval(400)).count == 1)
        lifecycle.observe([unresolved], now: now.addingTimeInterval(400))
        #expect(lifecycle.visible([unresolved], now: now.addingTimeInterval(500)).count == 1)
    }

}
