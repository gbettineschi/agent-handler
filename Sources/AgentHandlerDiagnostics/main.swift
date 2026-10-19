import Foundation
import AgentHandlerCore
import CodexDesktopAdapter

@main struct Diagnostics {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.contains("--probe") || arguments.contains("--demo") else {
            print("agent-handler-diagnostics --demo | --probe [--thread ID]")
            return
        }
        let core = RequestController(ledger: MemoryLedger())
        if arguments.contains("--demo") {
            let scope = RequestScope(installation: "fixture", conversation: "demo")
            let request = AttentionRequest(key: .init(scope: scope, turn: "turn", nativeID: .string("q")), owner: "fixture",
                title: "Synthetic question", content: .question(options: [], allowsText: true))
            let epoch = await core.begin(scope: scope)
            await core.observe(.init(scope: scope, epoch: epoch, revision: 1, requests: [request]))
            try await core.respond(key: request.key, fingerprint: request.fingerprint, answer: .text("Fixture answer"), using: FixtureTransport())
            guard await core.snapshot().first?.state == .accepted else { throw DiagnosticFailure.fixture }
            print("Synthetic controller round trip: passed. No native agent was contacted.")
            return
        }
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
        let ids: Set<String>
        if let offset = arguments.firstIndex(of: "--thread"), arguments.indices.contains(offset + 1) { ids = [arguments[offset + 1]] }
        else { ids = Set(try ThreadDiscovery.candidates(directory: directory).map(\.id)) }
        let adapter = DesktopAdapter(directory: directory, controller: core)
        await adapter.start(threadIDs: ids)
        let deadline = ContinuousClock.now + .seconds(12)
        while ContinuousClock.now < deadline {
            if await adapter.health().known > 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let health = await adapter.health()
        let output: [String: Any] = ["mode": "read-only", "candidateCount": ids.count,
            "compatibleOwnerStreams": health.known, "pendingQuestions": await core.snapshot().filter(\.needsAttention).count,
            "streamVersion": health.known > 0 ? 11 : 0, "status": health.message]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        await adapter.stop()
    }
    enum DiagnosticFailure: Error { case fixture }
    struct FixtureTransport: ResponseTransport {
        func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome { .accepted }
    }
}
