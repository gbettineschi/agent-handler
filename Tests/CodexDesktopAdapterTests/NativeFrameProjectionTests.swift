import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

struct NativeFrameProjectionTests {
    // Regression: the live 33 MB snapshot exhausted the raw JSON node allowance
    // before unused turn history could be projected out, losing every request.
    @Test(arguments: [false, true], ["hookRuns", "itemOutput", "turnSettings"])
    func largeUnusedHistoryStillDeliversQuestions(canonical: Bool, location: String) throws {
        var state = try JSONValue.parse(fixtureState(canonical: canonical, extraItems: [["type": "commandExecution", "id": "tool"]]))
        let turnPath: [JSONValue] = canonical
            ? [.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string("turn-key")]
            : [.string("turns"), .integer(0)]
        let suffix: [JSONValue] = location == "itemOutput" ? [.string("items"), .integer(1), .string("output")]
            : location == "turnSettings" ? [.string("params"), .string("unrelated")] : [.string("hookRuns")]
        if location == "turnSettings" {
            try DesktopPatches.apply([.object(["op": .string("add"), "path": .array(turnPath + [.string("params")]), "value": .object([:])])], to: &state)
        }
        let path = turnPath + suffix
        try DesktopPatches.apply([.object(["op": .string("add"), "path": .array(path),
            "value": .array(Array(repeating: .object(["unused": .array(Array(repeating: .integer(1), count: 24))]), count: 10_000))])], to: &state)
        let parsed = try DesktopProjection.decodeFrame(frame(state))["params"]["change"]["conversationState"]
        let questions = try DesktopQuestions.parse(state: parsed, threadID: "thread", owner: "desktop-owner", installation: "fixture")
        #expect(questions.map(\.title) == ["First?", "Second?"])
        #expect(questions[0].key.nativeID == .string("[\"request_user_input_async\",\"message\",0]"))
        #expect(ProjectionBudget.cost(parsed, available: ProjectionBudget.total) != nil)
    }

    @Test func projectionKeepsTheEntireApprovalAndEffectivePolicy() throws {
        var state = approvalState()
        try DesktopPatches.apply([.object(["op": .string("add"),
            "path": .array([.string("turns"), .integer(0), .string("hookRuns")]),
            "value": .array(Array(repeating: .integer(1), count: 210_000))])], to: &state)
        let parsed = try DesktopProjection.decodeFrame(frame(state))["params"]["change"]["conversationState"]
        let pending = try #require(approvals(parsed).first)
        #expect(pending.request.key.nativeID == .integer(7))
        #expect(pending.request.title.contains("printf test"))
        #expect(pending.responses == ["accept": .string("accept"), "decline": .string("decline")])
        #expect(parsed["requests"] == state["requests"])
    }

    @Test func requiredDataStillHasANodeLimit() throws {
        let state: JSONValue = .object(["requests": .array(Array(repeating: .integer(1), count: 210_000))])
        #expect(throws: (any Error).self) { _ = try DesktopProjection.decodeFrame(frame(state)) }
    }

    @Test(arguments: [#"[1,]"#, #"{"x":1,"x":2}"#, #"{"x":1,"\u0078":2}"#, #""\uD800""#, "1e400", String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130)])
    func discardedDataStillRequiresValidBoundedJSON(unused: String) throws {
        let json = #"{"params":{"change":{"conversationState":{"turns":[{"hookRuns":REPLACE}]}}}}"#.replacingOccurrences(of: "REPLACE", with: unused)
        #expect(throws: (any Error).self) { _ = try DesktopProjection.decodeFrame(Data(json.utf8)) }
    }

    @Test func discardedObjectScratchIsBoundedAndReleasedBetweenSiblings() throws {
        func object(_ count: Int) -> JSONValue {
            .object(Dictionary(uniqueKeysWithValues: (0..<count).map { (String(repeating: "k", count: 80) + String($0), JSONValue.integer(1)) }))
        }
        func data(_ value: JSONValue) throws -> Data {
            var state = try JSONValue.parse(fixtureState())
            try DesktopPatches.apply([.object(["op": .string("add"), "path": .array([.string("turns"), .integer(0), .string("hookRuns")]), "value": value])], to: &state)
            return try frame(state)
        }
        // Each fits individually; retaining sibling scratch would wrongly exhaust the cap.
        let parsed = try DesktopProjection.decodeFrame(data(.array([object(5_000), object(5_000)])))["params"]["change"]["conversationState"]
        #expect(try DesktopQuestions.parse(state: parsed, threadID: "thread", owner: "desktop-owner", installation: "fixture").map(\.title) == ["First?", "Second?"])
        #expect(throws: (any Error).self) { _ = try DesktopProjection.decodeFrame(data(object(10_000))) }
    }

    @Test func discardedMarkersPreserveLaterPatchPositions() throws {
        let state = try JSONValue.parse(fixtureState(extraItems: [["type": "commandExecution", "id": "tool", "output": ["nested": [1, 2, 3]]]]))
        var parsed = try DesktopProjection.decodeFrame(frame(state))["params"]["change"]["conversationState"]
        try DesktopPatches.apply([
            .object(["op": .string("replace"), "path": .array([.string("turns"), .integer(0), .string("items"), .integer(1), .string("output"), .string("nested"), .integer(0)]), "value": .integer(2)]),
            .object(["op": .string("replace"), "path": .array([.string("turns"), .integer(0), .string("items"), .integer(0), .string("questions"), .integer(0), .string("title")]), "value": .string("After patch?")])
        ], to: &parsed)
        #expect(try DesktopQuestions.parse(state: parsed, threadID: "thread", owner: "desktop-owner", installation: "fixture").map(\.title) == ["After patch?", "Second?"])
    }

    private func frame(_ state: JSONValue) throws -> Data {
        try RecordCoding.encoder().encode(JSONValue.object(["type": .string("broadcast"), "method": .string("thread-stream-state-changed"),
            "version": .integer(11), "params": .object(["hostId": .string("local"), "conversationId": .string("thread"),
                "change": .object(["type": .string("snapshot"), "revision": .integer(1), "conversationState": state])])]))
    }

    @Test func largeSnapshotReachesBothRequestScopesThroughTheSocket() async throws {
        var state = approvalState()
        try DesktopPatches.apply([
            .object(["op": .string("add"), "path": .array([.string("turns"), .integer(0), .string("hookRuns")]),
                "value": .array(Array(repeating: .integer(1), count: 210_000))]),
            .object(["op": .string("replace"), "path": .array([.string("turns"), .integer(0), .string("items")]),
                "value": .array([.object(["type": .string("agentMessage"), "id": .string("question"),
                    "questions": .array([.object(["title": .string("Still connected?")])])])])])
        ], to: &state)
        let server = try FixtureDesktopServer(state: state, fragmentSize: 65_536)
        defer { server.stop() }
        let controller = RequestController(ledger: MemoryLedger())
        let adapter = DesktopAdapter(directory: server.directory, controller: controller)
        await adapter.start(threadIDs: ["thread"])
        try await eventually { await controller.snapshot().filter { $0.state == .pending }.count == 2 }
        let requests = await controller.snapshot().map(\.request)
        #expect(requests.contains { $0.key.nativeID == .integer(7) && $0.title.contains("printf test") })
        #expect(requests.contains { $0.title == "Still connected?" })
        let wire = try DesktopIPC(path: server.directory.appendingPathComponent("ipc/ipc.sock").path, timeout: 3)
        defer { wire.close() }
        let direct = try wire.conversationState(source: "fixture-client", owner: "desktop-owner", threadID: "thread")
        #expect(try approvals(direct).count == 1)
        #expect(try DesktopQuestions.parse(state: direct, threadID: "thread", owner: "desktop-owner", installation: "fixture").first?.title == "Still connected?")
        #expect(server.answers.isEmpty)
        await adapter.stop()
    }
}
