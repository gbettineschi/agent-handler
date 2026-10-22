import Testing
import AgentHandlerCore
@testable import AgentHandlerApp
@testable import CodexDesktopAdapter

struct DiscoveryCatalogTests {
    @Test func disconnectedRunningHistoryMustLeaveRoomForANewConversation() {
        var store = ActivityStore()
        let ids = (1...16).map { "old-running-\($0)" }
        for id in ids {
            let scope = RequestScope(installation: "codex-desktop:fixture", conversation: id)
            let epoch = store.begin(scope: scope)
            store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .running, attention: .clear))
            store.invalidate(scope: scope, epoch: epoch)
        }
        let selected = DiscoveryCatalog.selection(pending: [], explicit: [], activities: store.views,
            observed: Set(ids), sourceOnly: [], candidates: ["new-chat"] + ids, unowned: Set(ids))
        #expect(selected.first == "new-chat")
        #expect(selected.count == 16)
    }
    @Test func temporaryObservationFailuresKeepActiveSubscriptionsAheadOfCatalogHistory() {
        var store = ActivityStore()
        let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "still-owned")
        let epoch = store.begin(scope: scope)
        store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .running, attention: .clear))
        store.invalidate(scope: scope, epoch: epoch)
        let selected = DiscoveryCatalog.selection(pending: [], explicit: [], activities: store.views,
            observed: ["still-owned"], sourceOnly: [], candidates: ["new-chat"])
        #expect(selected == ["still-owned", "new-chat"])
    }
    @Test func confirmedOwnerLossDoesNotDemoteUnresolvedInputOrExplicitTracking() {
        var store = ActivityStore()
        let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "needs-input")
        let epoch = store.begin(scope: scope)
        store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .running, attention: .required))
        store.invalidate(scope: scope, epoch: epoch)
        let ids: Set<String> = ["typed", "source-only", "explicit", "needs-input", "ordinary"]
        let selected = DiscoveryCatalog.selection(pending: ["typed"], explicit: ["explicit"], activities: store.views,
            observed: ids, sourceOnly: ["source-only"], candidates: ["new-chat"], unowned: ids)
        #expect(selected == ["typed", "source-only", "explicit", "needs-input", "new-chat", "ordinary"])
    }
    @Test func unreadableFormerOwnersCannotStarveNewChatsButRemainRetryCandidates() {
        let ids = Set((1...16).map { "unreadable-\($0)" })
        let selected = DiscoveryCatalog.selection(pending: [], explicit: [], activities: [], observed: ids,
            sourceOnly: [], candidates: ["new-chat"], unowned: ids)
        #expect(selected.first == "new-chat")
        #expect(selected.count == 16)
        #expect(!Set(selected).intersection(ids).isEmpty)
    }
    @Test func aFreshSourceOnlyWaitSurvivesSlotPressureEvenWhenItsPreviousActivityWasClear() {
        var store = ActivityStore()
        let ids = ["new-source-wait"] + (1...16).map { "active-\($0)" }
        for id in ids {
            let scope = RequestScope(installation: "codex-desktop:fixture", conversation: id)
            let epoch = store.begin(scope: scope)
            store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .running, attention: .clear))
        }
        let selected = DiscoveryCatalog.selection(pending: [], explicit: [], activities: store.views,
            observed: Set(ids), sourceOnly: ["new-source-wait"], candidates: ["new-chat"], unowned: ["new-source-wait"])
        #expect(selected.first == "new-source-wait")
        #expect(selected.count == 16)
    }
    @Test func disconnectedTerminalHistoryCannotOccupyEveryTrackingSlot() {
        var store = ActivityStore()
        let ids = (1...16).map { "finished-\($0)" }
        for id in ids {
            let scope = RequestScope(installation: "codex-desktop:fixture", conversation: id)
            let epoch = store.begin(scope: scope)
            store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .completed, attention: .clear))
            store.invalidate(scope: scope, epoch: epoch)
        }
        let selected = DiscoveryCatalog.selection(pending: [], explicit: [], activities: store.views, observed: Set(ids), sourceOnly: [], candidates: ["new-chat"] + ids)
        #expect(selected.first == "new-chat")
        #expect(selected.count == 16)
    }
    @Test func explicitTrackingIsNotStarvedByOrdinaryActiveRows() {
        var store = ActivityStore()
        for index in 1...16 {
            let scope = RequestScope(installation: "codex-desktop:fixture", conversation: "active-\(index)")
            let epoch = store.begin(scope: scope)
            store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .running, attention: .clear))
        }
        let selected = DiscoveryCatalog.selection(pending: ["pending"], explicit: ["explicit"], activities: store.views, observed: [], sourceOnly: [], candidates: [])
        #expect(selected.first == "pending")
        #expect(selected.contains("explicit"))
        #expect(selected.count == 16)
    }
    @Test func failuresRetainSubscriptionsUntilAnAuthoritativeSuccess() {
        var catalog = DiscoveryCatalog()
        catalog.update(.success([.init(id: "active", title: "Actual title")]))
        for _ in 0..<3 { catalog.update(.failure(ThreadDiscovery.Failure.database(operation: "schema", code: 5))) }
        #expect(catalog.candidates.map(\.id) == ["active"])
        #expect(catalog.candidates.first?.title == "Actual title")
        #expect(catalog.retryNeeded)
        #expect(catalog.diagnostic?.contains("busy") == true)
        #expect(catalog.warning?.contains("automatically") == true)
        catalog.update(.success([]))
        #expect(catalog.candidates.isEmpty)
        #expect(!catalog.retryNeeded)
        #expect(catalog.warning == nil)
    }
    @Test func initialFailureRetriesAndLaterSuccessClearsTheWarning() {
        var catalog = DiscoveryCatalog()
        catalog.update(.failure(ThreadDiscovery.Failure.unavailable))
        #expect(catalog.candidates.isEmpty)
        #expect(catalog.retryNeeded)
        catalog.update(.success([.init(id: "recovered", title: "Recovered chat")]))
        #expect(catalog.candidates.map(\.id) == ["recovered"])
        #expect(!catalog.retryNeeded)
        #expect(catalog.diagnostic == nil)
    }
}
