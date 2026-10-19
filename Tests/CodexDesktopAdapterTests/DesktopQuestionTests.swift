import Foundation
import Testing
import AgentHandlerCore
@testable import CodexDesktopAdapter

func fixtureState(questions: [[String: Any]] = [["title": "First?", "options": ["Yes", "No"]], ["title": "Second?"]],
                  canonical: Bool = false, extraItems: [[String: Any]] = []) throws -> Data {
    let turn: [String: Any] = ["turnId": "native-turn", "status": "inProgress", "items":
        [["type": "agentMessage", "id": "message", "questions": questions]] + extraItems]
    let state: [String: Any] = canonical
        ? ["requests": [], "turns": [], "turnHistory": ["kind": "canonical", "history": [
            "islands": [["entries": [["value": "turn-key"]], "newerBoundary": ["status": "exhausted"],
                         "olderBoundary": ["status": "exhausted"]]], "entitiesByKey": ["turn-key": turn]]]]
        : ["requests": [], "turns": [turn]]
    return try JSONSerialization.data(withJSONObject: state)
}
func parseQuestions(_ data: Data) throws -> [AttentionRequest] {
    try DesktopQuestions.decode(data, threadID: "thread", owner: "desktop-owner", installation: "fixture")
}

struct DesktopQuestionTests {
    @Test func incompleteHistoryCannotWithdrawOrResurrectQuestions() throws {
        var state = try JSONValue.parse(fixtureState())
        let empty = JSONValue.object(["turnId": .string("reply-turn"), "status": .string("inProgress"), "items": .array([])])
        var turns = state["turns"].arrayValue!; var old = turns[0].objectValue!; old["status"] = .string("completed")
        turns = [.object(old), empty]; state = .object(["turns": .array(turns)])
        #expect(throws: (any Error).self) { _ = try DesktopQuestions.parse(state: state, threadID: "thread", owner: "o", installation: "i") }
        let unknownContent = JSONValue.array([.object(["type": .string("futureUserInput")])])
        let unknown = JSONValue.object(["turnId": .string("reply-turn"), "status": .string("completed"),
            "items": .array([.object(["type": .string("userMessage"), "content": unknownContent])])])
        let future = JSONValue.object(["turns": .array([.object(old), unknown])])
        #expect(throws: (any Error).self) { _ = try DesktopQuestions.parse(state: future, threadID: "thread", owner: "o", installation: "i") }
        var partial = try JSONValue.parse(fixtureState())
        try DesktopPatches.apply([.object(["op": .string("add"), "path": .array([.string("turns"), .integer(0), .string("itemsPagination")]),
            "value": .object(["hasLoadedOldest": .bool(false)])])], to: &partial)
        DesktopProjection.compact(&partial)
        #expect(throws: (any Error).self) { _ = try DesktopQuestions.parse(state: partial, threadID: "thread", owner: "o", installation: "i") }
        var gap = try JSONValue.parse(fixtureState(canonical: true))
        // Distinct keys ensure this fails because of the history gap, not duplicate IDs.
        let earlier = JSONValue.object(["turnId": .string("earlier-turn"), "status": .string("completed"), "items": .array([])])
        let island = JSONValue.object(["entries": .array([.object(["value": .string("earlier-key")])]),
            "newerBoundary": .object(["status": .string("available")]),
            "olderBoundary": .object(["status": .string("exhausted")])])
        try DesktopPatches.apply([
            .object(["op": .string("add"), "path": .array([.string("turnHistory"), .string("history"), .string("entitiesByKey"), .string("earlier-key")]), "value": earlier]),
            .object(["op": .string("add"), "path": .array([.string("turnHistory"), .string("history"), .string("islands"), .integer(0)]), "value": island])
        ], to: &gap)
        #expect(throws: (any Error).self) { _ = try DesktopQuestions.parse(state: gap, threadID: "thread", owner: "o", installation: "i") }
    }
    @Test func malformedTurnStoresCannotEstablishWithdrawal() throws {
        let values = [
            #"{"turns":[{}]}"#,
            #"{"turns":[{"turnId":"t","status":"newStatus","items":[]}]}"#,
            #"{"turns":[],"turnHistory":{"kind":"newStore"}}"#,
            #"{"turns":[{"turnId":"t","status":"inProgress","items":[null]}]}"#,
            #"{"turns":[{"turnId":"t","status":"inProgress","items":[{"type":"newItem"}]}]}"#
        ]
        for value in values { #expect(throws: (any Error).self) { _ = try parseQuestions(Data(value.utf8)) } }
    }
    @Test func omittedOptionsCannotBecomeFreeText() throws {
        #expect(throws: (any Error).self) {
            _ = try parseQuestions(fixtureState(questions: [["title": "Q", "options": String(repeating: "x", count: 20_000)]]))
        }
    }
    @Test func multipleQuestionsAndCanonicalHistory() throws {
        for canonical in [false, true] {
            let requests = try parseQuestions(fixtureState(canonical: canonical))
            #expect(requests.count == 2)
            #expect(requests.first?.key.turn == "native-turn")
            #expect(requests.first?.key.nativeID == .string("[\"request_user_input_async\",\"message\",0]"))
        }
    }
    @Test func nativeAcceptedAnswerRemovesOnlyMatchingQuestion() throws {
        let text = "<send_user_message_question_reply>\n[{\"questionItemId\":\"[\\\"request_user_input_async\\\",\\\"message\\\",0]\",\"question\":\"First?\",\"answer\":\"Yes\"}]\n</send_user_message_question_reply>"
        let data = try fixtureState(extraItems: [["type": "steeringUserMessage", "status": "accepted", "input": [["type": "text", "text": text]]]])
        let requests = try parseQuestions(data)
        #expect(requests.count == 1)
        #expect(requests.first?.title == "Second?")
    }
    @Test func malformedOrTruncatedQuestionsDoNotEstablishWithdrawal() throws {
        for questions: [[String: Any]] in [[ ["title": 1] ], [["title": "Q", "options": [true]]], [["title": String(repeating: "x", count: 16_385)]]] {
            #expect(throws: (any Error).self) { _ = try parseQuestions(fixtureState(questions: questions)) }
        }
        #expect(throws: (any Error).self) { _ = try parseQuestions(Data("{}".utf8)) }
    }
    @Test func completionKeepsOutstandingQuestions() throws {
        let data = try fixtureState()
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        #expect(try parseQuestions(Data(text.utf8)).count == 2)
        for status in ["interrupted", "failed"] {
            #expect(try parseQuestions(Data(text.replacingOccurrences(of: "completed", with: status).utf8)).isEmpty)
        }
    }
    @Test func laterReplyRetainsSiblingButNewPromptEndsOldQuestions() throws {
        let first = try JSONValue.parse(fixtureState())["turns"].arrayValue![0]
        var original = first.objectValue!; original["status"] = .string("completed")
        let reply = #"<send_user_message_question_reply>[{"questionItemId":"[\"request_user_input_async\",\"message\",0]","question":"First?","answer":"Yes"}]</send_user_message_question_reply>"#
        func following(_ text: String) -> JSONValue {
            let content = JSONValue.array([.object(["type": .string("text"), "text": .string(text)])])
            return .object(["turnId": .string("reply-turn"), "status": .string("completed"),
                "items": .array([.object(["type": .string("userMessage"), "content": content])])])
        }
        let state = JSONValue.object(["turns": .array([.object(original), following(reply)])])
        let remaining = try DesktopQuestions.parse(state: state, threadID: "thread", owner: "desktop-owner", installation: "fixture")
        #expect(remaining.map(\.title) == ["Second?"])
        #expect(remaining.first?.key.turn == "native-turn")
        let unrelated = JSONValue.object(["turns": .array([.object(original), following("New task")])])
        #expect(try DesktopQuestions.parse(state: unrelated, threadID: "thread", owner: "desktop-owner", installation: "fixture").isEmpty)
    }
}
