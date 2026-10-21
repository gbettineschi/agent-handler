import Foundation
import Testing
import AgentHandlerCore
@testable import AgentHandlerApp

struct SessionSummaryTests {
    @Test func ownedSessionStaysVisibleBeforeItsActivityCanBeRead() {
        let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "thread")
        let rows = SessionSummary.rows(activities: [], requests: [], titles: ["thread": "Actual native title"], recentIDs: ["thread"], observedScopes: [scope])
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Actual native title")
        #expect(rows.first?.status == .unknown)
        #expect(rows.first?.turnID == nil)
        #expect(rows.first?.request == nil)
    }
    @Test func sourceOnlyApprovalCannotDisappearAsAnExpiredCompletion() {
        let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "thread")
        var store = ActivityStore(), lifecycle = SessionLifecycle()
        let epoch = store.begin(scope: scope)
        store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .completed, attention: .clear))
        let now = Date(timeIntervalSince1970: 1000)
        let rows = SessionSummary.rows(activities: store.views, requests: [], titles: ["thread": "Needs Codex"], recentIDs: [], observedScopes: [scope], sourceApprovalScopes: [scope])
        #expect(rows.first?.status == .needsInput)
        #expect(rows.first?.needsSourceApproval == true)
        #expect(rows.first?.request == nil)
        #expect(rows.first?.isFinished == false)
        lifecycle.observe(rows, now: now)
        #expect(lifecycle.visible(rows, now: now.addingTimeInterval(1000)).count == 1)
    }
    @Test func retainedUnavailableCardCannotMaskANewSourceOnlyRequest() async throws {
        let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "thread")
        let request = AttentionRequest(key: .init(scope: .init(installation: scope.installation + ":approvals", conversation: scope.conversation), turn: "turn", nativeID: .integer(7)),
            owner: "owner", title: "Earlier approval", content: .approval(choices: [.init(id: "accept", label: "Allow")]))
        let core = RequestController(ledger: MemoryLedger())
        let epoch = await core.begin(scope: request.key.scope)
        await core.observe(.init(scope: request.key.scope, epoch: epoch, revision: 1, requests: [request]))
        await core.invalidate(scope: request.key.scope, epoch: epoch)
        let retained = try #require(await core.snapshot().first)
        let rows = SessionSummary.rows(activities: [], requests: [retained], titles: [:], recentIDs: [], observedScopes: [scope], sourceApprovalScopes: [scope])
        #expect(rows.count == 1)
        #expect(rows.first?.status == .needsInput)
        #expect(rows.first?.request?.state == .unavailable)
        #expect(rows.first?.needsSourceApproval == true)
    }
    @Test func pendingRequestOutranksUnavailableSiblingWithoutJoiningAnotherProvider() async throws {
        let scope = RequestScope(installation: "desktop", conversation: "thread")
        let approvalScope = RequestScope(installation: "desktop:approvals", conversation: "thread")
        let core = RequestController(ledger: MemoryLedger())
        let old = AttentionRequest(key: .init(scope: approvalScope, turn: "old", nativeID: .string("approval")), owner: "owner", title: "Old approval", content: .approval(choices: [.init(id: "accept", label: "Allow once")]))
        let fresh = AttentionRequest(key: .init(scope: scope, turn: "new", nativeID: .string("question")), owner: "owner", title: "Current question", content: .question(options: [], allowsText: true))
        let oldEpoch = await core.begin(scope: approvalScope)
        await core.observe(.init(scope: approvalScope, epoch: oldEpoch, revision: 1, requests: [old]))
        await core.invalidate(scope: approvalScope, epoch: oldEpoch)
        let epoch = await core.begin(scope: scope)
        await core.observe(.init(scope: scope, epoch: epoch, revision: 1, requests: [fresh]))
        let views = await core.snapshot()
        let oldView = try #require(views.first { $0.id == old.key })
        let freshView = try #require(views.first { $0.id == fresh.key })
        var activity = ActivityStore()
        let other = RequestScope(installation: "claude-local-audit:fixture", conversation: "thread")
        let otherEpoch = activity.begin(scope: other)
        activity.observe(.init(scope: other, epoch: otherEpoch, revision: 1, turnID: "other", phase: .completed, attention: .clear))
        let rows = SessionSummary.rows(activities: activity.views, requests: [oldView, freshView], titles: [:], recentIDs: [])
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == scope }?.status == .needsInput)
        #expect(rows.first { $0.id == scope }?.request?.id == fresh.key)
        #expect(rows.first { $0.id == other }?.request == nil)
        #expect(rows.first { $0.id == other }?.status == .completed)
    }
    @Test func sessionsRemainVisibleWithoutRequestsInRecentOrder() {
        var store = ActivityStore()
        let older = RequestScope(installation: "desktop", conversation: "older")
        let newer = RequestScope(installation: "desktop", conversation: "newer")
        for (scope, phase) in [(older, ActivityPhase.completed), (newer, .running)] {
            let epoch = store.begin(scope: scope)
            store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: phase, attention: .clear))
        }
        let rows = SessionSummary.rows(activities: store.views, requests: [], titles: ["older": "Earlier task", "newer": "Latest task"], recentIDs: ["newer", "older"])
        #expect(rows.map(\.title) == ["Latest task", "Earlier task"])
        #expect(rows.map(\.status) == [.running, .completed])
        #expect(rows.allSatisfy { $0.request == nil })
    }

    @Test func lostSourceDoesNotPresentItsOldCompletionAsCurrent() {
        var store = ActivityStore()
        let scope = RequestScope(installation: "desktop", conversation: "thread")
        let epoch = store.begin(scope: scope)
        store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .completed, attention: .clear))
        store.invalidate(scope: scope, epoch: epoch)
        let rows = SessionSummary.rows(activities: store.views, requests: [], titles: [:], recentIDs: [])
        #expect(rows.count == 1)
        #expect(rows.first?.status == .unknown)
    }
}
