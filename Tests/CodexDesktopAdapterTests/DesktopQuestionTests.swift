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
    @Test(arguments: [false, true]) func imageViewingCannotHideOrCreateQuestions(canonical: Bool) throws {
        let image: [String: Any] = ["type": "imageView", "id": "image-tool",
            "questions": [["title": "Not an agent question"]],
            "content": [["type": "text", "text": "Not a native user answer"]]]
        let data = try fixtureState(canonical: canonical, extraItems: [image])
        let requests = try parseQuestions(data)
        #expect(requests.map(\.title) == ["First?", "Second?"])
        #expect(requests.map(\.key.nativeID) == [
            .string("[\"request_user_input_async\",\"message\",0]"),
            .string("[\"request_user_input_async\",\"message\",1]")])
        let state = try JSONValue.parse(fixtureState(questions: [], canonical: canonical, extraItems: [image]))
        let activity = try DesktopActivity.parse(state: state, threadID: "thread", owner: "desktop-owner", installation: "fixture")
        #expect(activity.attention == .clear)
    }
    @Test(arguments: [false, true]) func nativeFunctionOutputIsNeitherAQuestionNorAnAnswer(canonical: Bool) throws {
        // Observed on a real Desktop thread resumed by send_message_to_thread.
        let output: [String: Any] = ["type": "functionCallOutput", "id": "native-tool-result",
            "questions": [["title": "Not a question"]],
            "content": [["type": "text", "text": #"<send_user_message_question_reply>[{"questionItemId":"[\"request_user_input_async\",\"message\",0]","question":"First?","answer":"Yes"}]</send_user_message_question_reply>"#]]]
        let pending = try parseQuestions(fixtureState(canonical: canonical, extraItems: [output]))
        #expect(pending.map(\.title) == ["First?", "Second?"])
        let empty = try JSONValue.parse(fixtureState(questions: [], canonical: canonical, extraItems: [output]))
        let activity = try DesktopActivity.parse(state: empty, threadID: "thread", owner: "owner", installation: "fixture")
        #expect(activity.phase == .running)
        #expect(activity.attention == .clear)
        let endedData = try fixtureState(questions: [], canonical: canonical, extraItems: [output])
        let endedText = String(decoding: endedData, as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        let ended = try DesktopActivity.parse(state: JSONValue.parse(Data(endedText.utf8)), threadID: "thread", owner: "owner", installation: "fixture")
        #expect(ended.phase == .completed)
        #expect(ended.attention == .clear)
    }
    @Test(arguments: [false, true]) func toolResumedTurnRetainsEarlierQuestionsWithoutAnswerAuthority(canonical: Bool) throws {
        var original = try JSONValue.parse(fixtureState())["turns"].arrayValue![0].objectValue!
        original["status"] = .string("completed")
        original["items"] = .array([.object(["type": .string("userMessage"),
            "content": .array([.object(["type": .string("text"), "text": .string("Original task")])])])] + original["items"]!.arrayValue!)
        // Desktop's chat-management tool resumes a new turn with a tool output, not a user message.
        // Its contents cannot answer, withdraw or replace the earlier question group.
        let output = try JSONValue.parse(fixtureState(extraItems: [["type": "functionCallOutput", "id": "tool-result",
            "content": [["type": "text", "text": #"<send_user_message_question_reply>[{"questionItemId":"[\"request_user_input_async\",\"message\",0]","question":"First?","answer":"Yes"}]</send_user_message_question_reply>"#]]]]))["turns"].arrayValue![0]["items"].arrayValue!.last!
        let continuation = JSONValue.object(["turnId": .string("resumed-turn"), "status": .string("completed"), "items": .array([output])])
        func state(_ first: JSONValue) -> JSONValue {
            if !canonical { return .object(["requests": .array([]), "turns": .array([first, continuation])]) }
            return .object(["requests": .array([]), "turns": .array([]), "turnHistory": .object(["kind": .string("canonical"), "history": .object([
                "islands": .array([.object(["entries": .array([.object(["value": .string("first")]), .object(["value": .string("next")])]),
                    "olderBoundary": .object(["status": .string("exhausted")]), "newerBoundary": .object(["status": .string("exhausted")])])]),
                "entitiesByKey": .object(["first": first, "next": continuation])])])])
        }
        let pending = try DesktopQuestions.parse(state: state(.object(original)), threadID: "thread", owner: "owner", installation: "fixture")
        #expect(pending.map(\.title) == ["First?", "Second?"])
        #expect(pending.allSatisfy { $0.key.turn == "native-turn" })
        original["items"] = .array([original["items"]!.arrayValue!.first!])
        let completed = try DesktopActivity.parse(state: state(.object(original)), threadID: "thread", owner: "owner", installation: "fixture")
        #expect(completed.phase == .completed)
        #expect(completed.attention == .clear)
        if canonical {
            var partial = state(.object(original))
            try DesktopPatches.apply([
                .object(["op": .string("replace"), "path": .array([.string("turnHistory"), .string("history"), .string("islands"), .integer(0), .string("entries")]),
                    "value": .array([.object(["value": .string("next")])])]),
                .object(["op": .string("replace"), "path": .array([.string("turnHistory"), .string("history"), .string("islands"), .integer(0), .string("olderBoundary"), .string("status")]), "value": .string("available")])
            ], to: &partial)
            #expect(throws: (any Error).self) { _ = try DesktopQuestions.parse(state: partial, threadID: "thread", owner: "owner", installation: "fixture") }
        }
    }
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
