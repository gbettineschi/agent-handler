import Foundation
import Testing
@testable import AgentHandlerCore
@testable import AgentHandlerApp

struct SessionOrderingTests {
    func row(_ id: String, status: ActivityStatus = .running, input: String? = nil) -> SessionSummary {
        .init(id: .init(installation: "desktop", conversation: id), title: id, status: status, request: nil, humanInputID: input)
    }
    func request(_ row: SessionSummary, _ id: String) -> RequestView {
        .init(request: .init(key: .init(scope: row.id, turn: "turn", nativeID: .string(id)), owner: "owner", title: "Question", content: .question(options: [], allowsText: true)), state: .pending)
    }
    @Test func runningUpdatesAndMetadataReorderingDoNotMoveRows() {
        var order = SessionOrdering()
        let rows = [row("a"), row("b"), row("c")]
        order.observe(rows)
        var changed = rows.reversed().map { $0 }; changed[0].activityDetail = .thinking
        order.observe(changed)
        #expect(order.sorted(changed).map(\.title) == ["a", "b", "c"])
    }
    @Test func latestInterventionTakesPriorityOverHumanInputAndFinishes() {
        var order = SessionOrdering()
        let a = row("a"), b = row("b", status: .needsInput), c = row("c", status: .needsInput)
        order.observe([a, row("b"), row("c")])
        order.observe([a, b, row("c")], requests: [request(b, "first")])
        order.observe([a, b, c], requests: [request(b, "first"), request(c, "second")])
        let finished = row("a", status: .completed)
        order.observe([finished, b, c], requests: [request(b, "first"), request(c, "second")], newlyFinished: [finished])
        #expect(order.sorted([finished, b, c]).map(\.title) == ["c", "b", "a"])
        // Answering one of C's questions updates normal recency, not its older attention priority.
        order.observe([finished, b, c], requests: [request(b, "first"), request(c, "second"), request(b, "third")])
        #expect(order.sorted([finished, b, c]).map(\.title) == ["b", "c", "a"])
        order.observe([finished, b, row("c", input: "new-answer")], requests: [request(b, "first"), request(b, "third")])
        #expect(order.sorted([finished, b, row("c")]).map(\.title) == ["b", "c", "a"])
    }
    @Test func humanInputAndCompanionDecisionsMoveOnlyTheNormalGroup() {
        var order = SessionOrdering()
        let initial = [row("a", input: "a1"), row("b", input: "b1"), row("c", input: "c1")]
        order.observe(initial)
        let changed = [initial[0], initial[1], row("c", input: "c2")]
        order.observe(changed)
        #expect(order.sorted(changed).map(\.title) == ["c", "a", "b"])
        order.humanIntervened(in: initial[1].id)
        order.observe(changed)
        #expect(order.sorted(changed).map(\.title) == ["b", "c", "a"])
        order.observe(changed.reversed())
        #expect(order.sorted(changed).map(\.title) == ["b", "c", "a"])
    }
    @Test func restartAndUnknownGapsDoNotReplayInterventions() throws {
        var order = SessionOrdering()
        let a = row("a", status: .needsInput), b = row("b", status: .needsInput)
        order.observe([row("a"), row("b")])
        order.observe([a, row("b")], requests: [request(a, "a")])
        order.observe([a, b], requests: [request(a, "a"), request(b, "b")])
        var restored = try JSONDecoder().decode(SessionOrdering.self, from: JSONEncoder().encode(order))
        restored.observe([row("b", status: .unknown), row("a", status: .unknown)])
        restored.observe([b, a], requests: [request(b, "b"), request(a, "a")])
        #expect(restored.sorted([a, b]).map(\.title) == ["b", "a"])
    }
    @Test func resolvedRequestAndObservedFinishBecomeRecentWithoutTickReplay() {
        var order = SessionOrdering()
        let a = row("a"), b = row("b"), c = row("c", status: .needsInput)
        order.observe([a, b, row("c")])
        order.observe([a, b, c], requests: [request(c, "c")])
        order.observe([a, b, row("c")])
        #expect(order.sorted([a, b, row("c")]).map(\.title) == ["c", "a", "b"])
        let finished = row("b", status: .completed)
        order.observe([a, finished, row("c")], newlyFinished: [finished])
        order.observe([row("c"), a, finished])
        #expect(order.sorted([a, finished, row("c")]).map(\.title) == ["b", "c", "a"])
    }
    @Test func partiallyHydratedWaitingScopeCannotReplayOldRequests() throws {
        var order = SessionOrdering()
        let a = row("a", status: .needsInput), b = row("b", status: .needsInput)
        order.observe([row("a"), row("b")])
        order.observe([a, row("b")], requests: [request(a, "a-question"), request(a, "a-approval")])
        order.observe([a, b], requests: [request(a, "a-question"), request(a, "a-approval"), request(b, "b")])
        var restored = try JSONDecoder().decode(SessionOrdering.self, from: JSONEncoder().encode(order))
        // Activity and question/approval scopes hydrate independently after startup.
        restored.observe([a, b])
        restored.observe([a, b], requests: [request(a, "a-question"), request(b, "b")])
        restored.observe([a, b], requests: [request(a, "a-question"), request(a, "a-approval"), request(b, "b")])
        #expect(restored.sorted([a, b]).map(\.title) == ["b", "a"])
        restored.observe([row("a"), row("b")])
        #expect(restored.sorted([row("a"), row("b")]).map(\.title) == ["a", "b"])
    }
    @Test func delayedResolutionCannotPromoteTheSameInterventionTwice() {
        for nativeInput in [false, true] {
            var order = SessionOrdering()
            let a = row("a", status: .needsInput, input: "before"), b = row("b")
            order.observe([a, b], requests: [request(a, "a")])
            let answered = row("a", status: .needsInput, input: nativeInput ? "answer" : "before")
            if !nativeInput { order.humanIntervened(in: a.id) }
            order.observe([answered, b], requests: [request(a, "a")])
            order.humanIntervened(in: b.id)
            // Native waiting status lags the already recorded human response.
            order.observe([answered, b])
            let cleared = row("a", input: nativeInput ? "answer" : "before")
            order.observe([cleared, b])
            #expect(order.sorted([cleared, b]).map(\.title) == ["b", "a"])
        }
    }
    @Test func markerlessCurrentBaselineStillRecognizesTheNextHumanMessage() {
        var order = SessionOrdering()
        order.observe([row("a"), row("b")])
        let next = [row("a"), row("b", input: "first-real-message")]
        order.observe(next)
        #expect(order.sorted(next).map(\.title) == ["b", "a"])
        var hydrating = SessionOrdering()
        hydrating.observe([row("a", status: .unknown), row("b", status: .unknown)])
        hydrating.observe(next)
        #expect(hydrating.sorted(next).map(\.title) == ["a", "b"])
    }
    @Test func sourceApprovalAfterAnotherAnswerIsADistinctHumanEvent() {
        var order = SessionOrdering()
        let a = row("a", status: .needsInput, input: "before"), b = row("b", input: "b-before")
        let question = request(a, "question"), permission = request(a, "permission")
        order.observe([a, b], requests: [question, permission])
        let answered = row("a", status: .needsInput, input: "question-answer")
        order.observe([answered, b], requests: [permission])
        let newerB = row("b", input: "b-message")
        order.observe([answered, newerB], requests: [permission])
        order.approvalsClosed([permission.id])
        let cleared = row("a", input: "question-answer")
        order.observe([cleared, newerB])
        #expect(order.sorted([cleared, newerB]).map(\.title) == ["a", "b"])
    }
    @Test(arguments: [false, true]) func approvalClosureEchoCannotReorderAcrossRestart(local: Bool) throws {
        var order = SessionOrdering()
        let a = row("a", status: .needsInput), b = row("b")
        let permission = request(a, "permission")
        order.observe([a, b], requests: [permission])
        if local { order.humanIntervened(in: a.id, requestKey: permission.id) }
        else { order.approvalsClosed([permission.id]) }
        order.humanIntervened(in: b.id)
        var restored = try JSONDecoder().decode(SessionOrdering.self, from: JSONEncoder().encode(order))
        restored.approvalsClosed([permission.id, permission.id])
        restored.observe([row("a"), b])
        restored.approvalsClosed([permission.id, request(b, "never-seen").id])
        #expect(restored.sorted([row("a"), b]).map(\.title) == ["b", "a"])
    }
}
