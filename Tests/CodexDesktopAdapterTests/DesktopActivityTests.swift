import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

struct DesktopActivityTests {
    func parse(_ state: JSONValue) throws -> (turnID: String, phase: ActivityPhase, attention: ActivityAttention) {
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

    @Test func humanApprovalAndAutomaticReviewAreDifferent() throws {
        #expect(try parse(approvalState()).attention == .required)
        #expect(try parse(approvalState(reviewer: "auto_review")).attention == .unknown)
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
}
