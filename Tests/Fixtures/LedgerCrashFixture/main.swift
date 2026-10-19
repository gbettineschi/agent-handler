import Foundation
import Darwin
import AgentHandlerCore

// Test-only subprocess. Never opens the application's real ledger or contacts an agent.
@main struct LedgerCrashFixture {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3, ["reserved", "accepted", "notSent"].contains(arguments[2]) else { exit(64) }
        let directory = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        guard directory.lastPathComponent.hasPrefix("ah-crash-test-"),
              directory.deletingLastPathComponent().resolvingSymlinksInPath() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath() else { exit(64) }
        let ledger = try SQLiteLedger(url: directory.appendingPathComponent("ledger.sqlite"))
        let key = RequestKey(scope: .init(installation: "crash-fixture", conversation: "conversation"), turn: "turn", nativeID: .string("question"))
        let attempt = UUID()
        try ledger.reserve(key: key, fingerprint: "synthetic-fingerprint", attemptID: attempt)
        if arguments[2] == "accepted" { try ledger.finish(key: key, attemptID: attempt, outcome: .accepted) }
        if arguments[2] == "notSent" { try ledger.finish(key: key, attemptID: attempt, outcome: .notSent) }
        withExtendedLifetime(ledger) { _ = Darwin.kill(getpid(), SIGKILL) }
        exit(70) // Reaching this means the crash test did not run as intended.
    }
}
