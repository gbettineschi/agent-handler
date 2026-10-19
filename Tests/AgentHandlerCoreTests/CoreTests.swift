import Foundation
import Testing
@testable import AgentHandlerCore

let scope = RequestScope(installation: "fixture", conversation: "thread")
func question(_ id: NativeID = .string("q1"), title: String = "Choose", in target: RequestScope = scope) -> AttentionRequest {
    AttentionRequest(key: .init(scope: target, turn: "turn", nativeID: id), owner: "owner", title: title,
                     content: .question(options: [.init(id: "a", label: "One")], allowsText: true))
}
func observation(_ requests: [AttentionRequest], epoch: UUID, revision: Int64 = 1, in target: RequestScope = scope) -> RequestSnapshot {
    .init(scope: target, epoch: epoch, revision: revision, requests: requests)
}

struct CoreTests {
    @Test func independentRequestsWithSameWording() {
        var store = RequestStore()
        let epoch = store.begin(scope: scope)
        let applied = store.apply(snapshot: observation([question(), question(.string("q2"))], epoch: epoch))
        #expect(applied)
        #expect(store.views.filter(\.needsAttention).count == 2)
    }

    @Test func integerAndStringIDsAreDifferent() {
        #expect(question(.integer(7)).key != question(.string("7")).key)
        #expect(question(.integer(7)).key.digest != question(.string("7")).key.digest)
    }

    @Test func oldEpochAndRevisionCannotReopenClosedRequest() {
        var store = RequestStore()
        let old = store.begin(scope: scope)
        _ = store.apply(snapshot: observation([question()], epoch: old))
        let current = store.begin(scope: scope)
        let oldApplied = store.apply(snapshot: observation([question()], epoch: old, revision: 99))
        #expect(!oldApplied)
        _ = store.apply(snapshot: observation([], epoch: current, revision: 3))
        let staleApplied = store.apply(snapshot: observation([question()], epoch: current, revision: 2))
        #expect(!staleApplied)
        #expect(store.views.filter(\.needsAttention).isEmpty)
    }

    @Test func snapshotOnlyClosesItsOwnScope() {
        var store = RequestStore()
        let other = RequestScope(installation: "fixture", conversation: "other")
        let one = store.begin(scope: scope), two = store.begin(scope: other)
        _ = store.apply(snapshot: observation([question()], epoch: one))
        _ = store.apply(snapshot: observation([question(in: other)], epoch: two, in: other))
        _ = store.apply(snapshot: observation([], epoch: one, revision: 2))
        #expect(store.views.filter(\.needsAttention).map(\.request.key.scope) == [other])
    }

    @Test func malformedAndDisconnectedAreUnknownNotEmpty() {
        var store = RequestStore()
        let epoch = store.begin(scope: scope)
        _ = store.apply(snapshot: observation([question()], epoch: epoch))
        let malformedApplied = store.apply(snapshot: observation([question(), question()], epoch: epoch, revision: 2))
        #expect(!malformedApplied)
        #expect(store.views.first?.state == .unavailable)
        #expect(store.views.first?.needsAttention == true)
        store.invalidate(scope: scope, epoch: epoch)
        #expect(store.views.count == 1)
    }

    @Test func changedContentChangesFingerprintButRevisionDoesNot() {
        #expect(question().fingerprint != question(title: "Changed").fingerprint)
        #expect(question().fingerprint == question().fingerprint)
    }
}
