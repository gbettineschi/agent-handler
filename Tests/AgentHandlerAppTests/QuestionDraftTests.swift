import Testing
import AgentHandlerCore
@testable import AgentHandlerApp

struct QuestionDraftTests {
    let options = [ResponseOption(id: "blue", label: "Blue")]

    @Test func cannotSubmitAnOptionRemovedByTheSource() {
        var draft = QuestionDraft()
        draft.select("blue")
        #expect(draft.answer(options: options, allowsText: true) == .option("blue"))
        #expect(draft.answer(options: [], allowsText: true) == nil)
    }

    @Test func typingAndChoosingAreMutuallyExclusive() {
        var draft = QuestionDraft()
        draft.select("blue")
        draft.write("Green")
        #expect(draft.answer(options: options, allowsText: true) == .text("Green"))
        #expect(draft.answer(options: options, allowsText: false) == nil)
        draft.select("blue")
        #expect(draft.text.isEmpty)
        #expect(draft.answer(options: options, allowsText: true) == .option("blue"))
    }

    @Test func textUsesTheWireByteLimitWithoutTrimmingTheAnswer() {
        var draft = QuestionDraft()
        draft.write("  \n")
        #expect(draft.answer(options: [], allowsText: true) == nil)
        draft.write("  keep these spaces  ")
        #expect(draft.answer(options: [], allowsText: true) == .text("  keep these spaces  "))
        draft.write(String(repeating: "é", count: 8192))
        #expect(draft.answer(options: [], allowsText: true) != nil)
        draft.write(String(repeating: "é", count: 8193))
        #expect(draft.answer(options: [], allowsText: true) == nil)
    }
}
