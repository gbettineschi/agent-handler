import Foundation
import AgentHandlerCore

/// Built-in examples use the real controller and a memory ledger, never an agent.
enum DemoScenario: String, CaseIterable, Identifiable {
    case questions, approval, longContent, unavailable, uncertain, empty
    var id: Self { self }
    var title: String {
        switch self {
        case .questions: "Questions"
        case .approval: "Command approval"
        case .longContent: "Long content"
        case .unavailable: "Connection lost"
        case .uncertain: "Uncertain delivery"
        case .empty: "No requests"
        }
    }

    func requests(scope: RequestScope, turn: String) -> [AttentionRequest] {
        func request(_ id: String, _ title: String, _ content: RequestContent, details: ApprovalDetails? = nil) -> AttentionRequest {
            AttentionRequest(key: .init(scope: scope, turn: turn, nativeID: .string(id)), owner: "demo", title: title, content: content, approvalDetails: details)
        }
        let question = request("first", "Which option should I use?",
            .question(options: [.init(id: "simple", label: "Keep it simple"), .init(id: "details", label: "Show the details")], allowsText: true))
        switch self {
        case .questions:
            return [question, request("second", "Anything else I should consider?", .question(options: [], allowsText: true))]
        case .approval:
            return [request("approval", "Run command?\n\n/usr/bin/printf 'This is a synthetic approval — no command will run.\\n'\n\nDirectory: /Users/example/Projects/agent-handler\n\nAllow a harmless connection check?",
                .approval(choices: [.init(id: "accept", label: "Allow once"),
                    .init(id: "rule", label: "Allow and save command rule: [\"/usr/bin/printf\",\"This is a synthetic approval — no command will run.\"]"),
                    .init(id: "cancel", label: "Cancel turn")]), details: .init(
                        subject: .command(command: "/usr/bin/printf 'This is a synthetic approval — no command will run.\\n'", directory: "/Users/example/Projects/agent-handler", reason: "Allow a harmless connection check?"),
                        persistentActions: ["rule": .commandRule(prefix: ["/usr/bin/printf", "This is a synthetic approval — no command will run."])]))]
        case .longContent:
            return [request("long", "How should I handle the remaining changes?\n\nThere are several independent tasks in this example. Review the choices, scroll through the complete text, or write your own answer. Your draft stays here if you close the panel or open Settings.",
                .question(options: [
                    .init(id: "small", label: "Keep the change small and finish the current task before taking on anything else."),
                    .init(id: "review", label: "Review the command, its working directory, and the full permission scope before making a decision."),
                    .init(id: "custom", label: "Leave the remaining tasks for later. Preserve the existing files and report anything that still needs verification.")
                ], allowsText: true))]
        case .unavailable: return [question]
        case .uncertain:
            return [request("uncertain", "Run command?\n\n/usr/bin/printf 'Synthetic delivery check\\n'\n\nDirectory: /Users/example/Projects/agent-handler",
                .approval(choices: [.init(id: "accept", label: "Allow once"), .init(id: "cancel", label: "Cancel turn")]),
                details: .init(subject: .command(command: "/usr/bin/printf 'Synthetic delivery check\\n'", directory: "/Users/example/Projects/agent-handler", reason: nil)))]
        case .empty: return []
        }
    }
}

struct DemoTransport: ResponseTransport {
    let outcome: DeliveryOutcome
    init(outcome: DeliveryOutcome = .accepted) { self.outcome = outcome }
    func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome { outcome }
}
