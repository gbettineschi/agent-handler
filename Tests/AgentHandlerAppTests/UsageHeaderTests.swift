import Foundation
import Testing
import CodexDesktopAdapter
@testable import AgentHandlerApp

struct UsageHeaderTests {
    @Test func countdownRoundsUpAndDoesNotPromiseAnAutomaticReset() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (seconds, expected) in [(500_000, "6d"), (86_400, "1d"), (3_601, "2h"), (3_600, "1h"), (30, "1m")] {
            let data = Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":29,\"resetsAt\":\(1_800_000_000 + seconds)}}}".utf8)
            let snapshot = try CodexUsageSnapshot.decode(data, fetchedAt: now)
            let header = UsageHeader(snapshot: snapshot, now: now)
            #expect(header.remaining == "71% left")
            #expect(header.reset == expected)
            #expect(header.help.contains("reset"))
            #expect(UsageHeader(snapshot: snapshot, now: now.addingTimeInterval(Double(seconds))).remaining == "—")
        }
        #expect(UsageHeader(snapshot: nil, now: now).remaining == "—")
    }
}
