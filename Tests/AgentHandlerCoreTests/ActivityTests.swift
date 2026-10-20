import Foundation
import Testing
@testable import AgentHandlerCore

struct ActivityTests {
    let scope = RequestScope(installation: "source", conversation: "conversation")

    @Test func nativeOutcomesRemainDistinct() {
        var store = ActivityStore()
        let epoch = store.begin(scope: scope)
        let cases: [(ActivityPhase, ActivityStatus)] = [
            (.running, .running), (.completed, .completed), (.failed, .failed), (.cancelled, .cancelled)
        ]
        for (index, pair) in cases.enumerated() {
            #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: Int64(index),
                turnID: "turn-\(index)", phase: pair.0, attention: .clear)))
            #expect(store.views.first?.status == pair.1)
        }
    }

    @Test func pendingOrUnknownAttentionPreventsACompletionClaim() {
        var store = ActivityStore()
        let epoch = store.begin(scope: scope)
        #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 1,
            turnID: "t", phase: .completed, attention: .required)))
        #expect(store.views.first?.status == .needsInput)
        #expect(store.views.first?.phase == .completed)
        #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 2,
            turnID: "t", phase: .completed, attention: .unknown)))
        #expect(store.views.first?.status == .unknown)
        store.invalidate(scope: scope, epoch: epoch)
        #expect(store.views.first?.isCurrent == false)
        #expect(store.views.first?.status == .unknown)
    }

    @Test func disconnectRequiresANewerSnapshot() {
        var store = ActivityStore()
        let epoch = store.begin(scope: scope)
        let original = ActivitySnapshot(scope: scope, epoch: epoch, revision: 4,
            turnID: "t", phase: .running, attention: .clear)
        #expect(true == store.observe(original))
        store.invalidate(scope: scope, epoch: epoch)
        #expect(store.views.first?.status == .unknown)
        #expect(false == store.observe(original))
        #expect(store.views.first?.status == .unknown)
        #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 5,
            turnID: "t", phase: .completed, attention: .clear)))
        #expect(store.views.first?.status == .completed)
    }

    @Test func oldOwnersCannotReviveOrInvalidateReplacementActivity() {
        var store = ActivityStore()
        let old = store.begin(scope: scope)
        #expect(true == store.observe(.init(scope: scope, epoch: old, revision: 99,
            turnID: "old", phase: .running, attention: .clear)))
        let current = store.begin(scope: scope)
        #expect(store.views.first?.status == .unknown)
        #expect(false == store.observe(.init(scope: scope, epoch: old, revision: 100,
            turnID: "old", phase: .completed, attention: .clear)))
        #expect(true == store.observe(.init(scope: scope, epoch: current, revision: 0,
            turnID: "new", phase: .running, attention: .clear)))
        store.invalidate(scope: scope, epoch: old)
        #expect(store.views.first?.status == .running)
        #expect(false == store.observe(.init(scope: scope, epoch: current, revision: 0,
            turnID: "new", phase: .completed, attention: .clear)))
        #expect(store.views.first?.turnID == "new")
    }

    @Test func invalidIdentityConsumesItsRevisionWithoutEstablishingCompletion() {
        for invalid in ["", String(repeating: "x", count: 257)] {
            var store = ActivityStore()
            let epoch = store.begin(scope: scope)
            #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 1,
                turnID: "t", phase: .running, attention: .clear)))
            #expect(false == store.observe(.init(scope: scope, epoch: epoch, revision: 3,
                turnID: invalid, phase: .completed, attention: .clear)))
            #expect(store.views.first?.status == .unknown)
            #expect(false == store.observe(.init(scope: scope, epoch: epoch, revision: 2,
                turnID: "t", phase: .completed, attention: .clear)))
            #expect(store.views.first?.status == .unknown)
        }
    }

    @Test func scopesStayIndependentAndUnfollowedRecordsCannotReturn() {
        var store = ActivityStore()
        let other = RequestScope(installation: "other-source", conversation: "conversation")
        let firstEpoch = store.begin(scope: scope), secondEpoch = store.begin(scope: other)
        #expect(true == store.observe(.init(scope: scope, epoch: firstEpoch, revision: 1,
            turnID: "t", phase: .running, attention: .clear)))
        #expect(true == store.observe(.init(scope: other, epoch: secondEpoch, revision: 1,
            turnID: "t", phase: .completed, attention: .clear)))
        store.remove(scope: scope)
        #expect(false == store.observe(.init(scope: scope, epoch: firstEpoch, revision: 2,
            turnID: "t", phase: .completed, attention: .clear)))
        #expect(store.views.count == 1)
        #expect(store.views.first?.id == other)
        #expect(store.views.first?.status == .completed)
    }
    @Test func activityHintsClearOnInputCompletionAndDisconnect() throws {
        var store = ActivityStore()
        let epoch = store.begin(scope: scope)
        #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "t", phase: .running, attention: .clear, detail: .thinking)))
        #expect(store.views.first?.detail == .thinking)
        store.invalidate(scope: scope, epoch: epoch)
        #expect(store.views.first?.detail == nil)
        #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 2, turnID: "t", phase: .running, attention: .required, detail: .thinking)))
        #expect(store.views.first?.detail == nil)
        #expect(store.views.first?.status == .needsInput)
        #expect(true == store.observe(.init(scope: scope, epoch: epoch, revision: 3, turnID: "t", phase: .completed, attention: .clear, detail: .runningCommand)))
        #expect(store.views.first?.detail == nil)
        #expect(store.views.first?.status == .completed)
        #expect(false == store.observe(.init(scope: scope, epoch: epoch, revision: 2, turnID: "t", phase: .running, attention: .clear, detail: .thinking)))
        #expect(store.views.first?.detail == nil)
    }

}
