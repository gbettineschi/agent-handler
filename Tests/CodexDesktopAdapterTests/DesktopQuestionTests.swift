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
            "islands": [["entries": [["value": "turn-key"]]]], "entitiesByKey": ["turn-key": turn]]]]
        : ["requests": [], "turns": [turn]]
    return try JSONSerialization.data(withJSONObject: state)
}
func parseQuestions(_ data: Data) throws -> [AttentionRequest] {
    try DesktopQuestions.decode(data, threadID: "thread", owner: "desktop-owner", installation: "fixture")
}

struct DesktopQuestionTests {
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
    @Test func completionClosesQuestions() throws {
        let data = try fixtureState()
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "inProgress", with: "completed")
        #expect(try parseQuestions(Data(text.utf8)).isEmpty)
    }
}
