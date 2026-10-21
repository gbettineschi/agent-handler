import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

struct DesktopActivityTests {
    @Test func humanInputMarkerIgnoresToolOutputAndUnacceptedSteering() {
        func turn(_ items: [JSONValue]) -> JSONValue { .object(["turnId": .string("turn"), "items": .array(items)]) }
        func item(_ type: String, _ id: String, _ status: String? = nil) -> JSONValue {
            .object(["type": .string(type), "id": .string(id), "status": status.map(JSONValue.string) ?? .null])
        }
        let user = item("userMessage", "user")
        let output = item("functionCallOutput", "tool")
        #expect(DesktopActivity.humanInputID(in: turn([user])) == "turn:user")
        #expect(DesktopActivity.humanInputID(in: turn([user, output])) == "turn:user")
        #expect(DesktopActivity.humanInputID(in: turn([output])) == nil)
        #expect(DesktopActivity.humanInputID(in: turn([user, item("steeringUserMessage", "rejected", "rejected")])) == "turn:user")
        #expect(DesktopActivity.humanInputID(in: turn([user, item("steeringUserMessage", "answer", "accepted")])) == "turn:answer")
        #expect(DesktopActivity.humanInputID(in: turn([item("userMessage", "")])) == nil)
    }
    func parse(_ state: JSONValue) throws -> (turnID: String, phase: ActivityPhase, attention: ActivityAttention, detail: ActivityDetail?, humanInputID: String?) {
        try DesktopActivity.parse(state: state, threadID: "thread", owner: "desktop-owner", installation: "fixture")
    }

    @Test(arguments: [false, true]) func explicitNativeOutcomes(canonical: Bool) throws {
        let cases: [(String, ActivityPhase)] = [
            ("inProgress", .running), ("completed", .completed), ("failed", .failed), ("interrupted", .cancelled)
        ]
        for (wire, phase) in cases {
            let text = String(decoding: try fixtureState(questions: [], canonical: canonical), as: UTF8.self)
                .replacingOccurrences(of: "inProgress", with: wire)
            let value = try parse(JSONValue.parse(Data(text.utf8)))
            #expect(value.turnID == "native-turn")
            #expect(value.phase == phase)
            #expect(value.attention == .clear)
        }
    }

    @Test func completedTurnWithAQuestionStillNeedsInput() throws {
        let text = String(decoding: try fixtureState(), as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        let value = try parse(JSONValue.parse(Data(text.utf8)))
        #expect(value.phase == .completed)
        #expect(value.attention == .required)
    }

    @Test func nativeManualQueueRequiresInputRegardlessOfTheTurnReviewer() throws {
        #expect(try parse(approvalState()).attention == .required)
        #expect(try parse(approvalState(reviewer: "auto_review")).attention == .required)
        var automaticOnly = try JSONValue.parse(fixtureState(questions: []))
        try DesktopPatches.apply([.object(["op": .string("add"), "path": .array([.string("currentPermissions")]),
            "value": approvalState(reviewer: "auto_review")["turns"].arrayValue![0]["params"]])], to: &automaticOnly)
        #expect(try parse(automaticOnly).attention == .clear)
    }

    @Test func unknownRequestsAndMalformedQuestionHistoryCannotLookClear() throws {
        let base = try JSONValue.parse(fixtureState(questions: []))
        let cases: [JSONValue] = [
            .null,
            .array([.object(["method": .string("future/request"), "completed": .bool(false)])]),
            .array([.object(["method": .string("future/request"), "completed": .integer(1)])]),
            .array([.null])
        ]
        for requests in cases {
            var fields = base.objectValue!; fields["requests"] = requests
            #expect(try parse(.object(fields)).attention == .unknown)
        }
        var complete = base.objectValue!
        complete["requests"] = .array([.object(["method": .string("future/request"), "completed": .bool(true)])])
        #expect(try parse(.object(complete)).attention == .clear)
        let malformed = try JSONValue.parse(fixtureState(questions: [["title": 17]]))
        #expect(try parse(malformed).attention == .unknown)
        // A known question still requires input even when a different request kind is unsupported.
        var knownQuestion = try JSONValue.parse(fixtureState()).objectValue!
        knownQuestion["requests"] = .array([.object(["method": .string("future/request")])])
        #expect(try parse(.object(knownQuestion)).attention == .required)
    }

    @Test func missingNewestBoundaryAndAmbiguousOverlayCannotClaimCompletion() throws {
        var canonical = try JSONValue.parse(fixtureState(questions: [], canonical: true))
        let prefix: [JSONValue] = [.string("turnHistory"), .string("history"), .string("islands"), .integer(0), .string("newerBoundary"), .string("status")]
        try DesktopPatches.apply([.object(["op": .string("replace"), "path": .array(prefix), "value": .string("available")])], to: &canonical)
        #expect(throws: (any Error).self) { _ = try parse(canonical) }
        var overlay = try JSONValue.parse(fixtureState(questions: [], canonical: true)).objectValue!
        overlay["turns"] = .array([.object(["turnId": .string("overlay"), "status": .string("completed"), "items": .array([])])])
        #expect(throws: (any Error).self) { _ = try parse(.object(overlay)) }
        for text in [#"{}"#, #"{"requests":[],"turns":[]}"#,
                     #"{"requests":[],"turns":[{"turnId":"t","status":"newStatus","items":[]}]}"#] {
            #expect(throws: (any Error).self) { _ = try parse(JSONValue.parse(Data(text.utf8))) }
        }
    }

    @Test func aRunningTurnBeforeTheLastTurnCannotLookComplete() throws {
        let running = try JSONValue.parse(fixtureState(questions: []))["turns"].arrayValue![0]
        let completed: JSONValue = .object(["turnId": .string("later"), "status": .string("completed"), "items": .array([])])
        let state: JSONValue = .object(["requests": .array([]), "turns": .array([running, completed])])
        #expect(throws: (any Error).self) { _ = try parse(state) }
    }

    @Test func knownPendingContinuationsPreventACompletionClaim() throws {
        let text = String(decoding: try fixtureState(questions: []), as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        let base = try JSONValue.parse(Data(text.utf8)).objectValue!
        for (key, value): (String, JSONValue) in [
            ("unconfirmedTurnSubmissions", .array([.object(["id": .string("next")])])),
            ("threadGoal", .object(["status": .string("active")])),
            ("queuedMessages", .array([.object(["id": .string("next")])]))
        ] {
            var fields = base; fields[key] = value
            #expect(throws: (any Error).self) { _ = try parse(.object(fields)) }
        }
    }
    @Test func activityHintUsesOnlyLatestCurrentTurnItem() {
        func turn(_ items: [JSONValue], status: String = "inProgress") -> JSONValue {
            .object(["status": .string(status), "items": .array(items)])
        }
        let reasoning: JSONValue = .object(["type": .string("reasoning")])
        let command: JSONValue = .object(["type": .string("commandExecution"), "status": .string("inProgress")])
        #expect(DesktopActivity.detail(in: turn([reasoning])) == .thinking)
        #expect(DesktopActivity.detail(in: turn([reasoning, command])) == .runningCommand)
        let finished: JSONValue = .object(["type": .string("commandExecution"), "status": .string("completed")])
        #expect(DesktopActivity.detail(in: turn([reasoning, finished])) == nil)
        #expect(DesktopActivity.detail(in: turn([reasoning], status: "completed")) == nil)
        #expect(DesktopActivity.detail(in: turn([.object(["type": .string("future")])])) == nil)
        #expect(DesktopActivity.detail(in: turn([.object(["type": .string("commandExecution")])])) == nil)
    }

    @Test func supportedActiveHintsRequireNativeItemStatus() {
        let cases: [(String, ActivityDetail)] = [("agentMessage", .responding), ("fileChange", .editingFiles),
            ("webSearch", .searching), ("mcpToolCall", .usingTool), ("collabAgentToolCall", .coordinating)]
        for (type, expected) in cases {
            func turn(_ status: String) -> JSONValue {
                .object(["status": .string("inProgress"), "items": .array([.object(["type": .string(type), "status": .string(status)])])])
            }
            #expect(DesktopActivity.detail(in: turn("inProgress")) == expected)
            #expect(DesktopActivity.detail(in: turn("completed")) == nil)
            #expect(DesktopActivity.detail(in: turn("future")) == nil)
        }
    }

}
