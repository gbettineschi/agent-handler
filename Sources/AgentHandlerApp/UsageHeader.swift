import Foundation
import CodexDesktopAdapter

struct UsageHeader {
    let remaining: String
    let reset: String?
    let help: String
    init(snapshot: CodexUsageSnapshot?, now: Date) {
        guard let snapshot, let window = snapshot.displayWindow(at: now) else {
            remaining = "—"; reset = nil
            help = "Codex usage unavailable. Requires the signed-in Codex account; refreshes once a minute."
            return
        }
        remaining = "\(window.remainingPercent)% left"
        reset = window.resetsAt.map { Self.countdown($0.timeIntervalSince(now)) }
        let windows = snapshot.windows.map { window in
            let duration = window.durationMinutes.map {
                $0 % 1440 == 0 ? "\($0 / 1440)-day" : $0 % 60 == 0 ? "\($0 / 60)-hour" : "\($0)-minute"
            } ?? "Usage"
            let date = window.resetsAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unavailable"
            return "\(duration) window: \(window.remainingPercent)% remaining · reset \(date)"
        }.joined(separator: "\n")
        help = "Codex account usage\n\(windows)\nShows the least remaining allowance. Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)); refreshes once a minute."
    }
    private static func countdown(_ seconds: TimeInterval) -> String {
        if seconds >= 86_400 { return "\(Int(ceil(seconds / 86_400)))d" }
        if seconds >= 3_600 { return "\(Int(ceil(seconds / 3_600)))h" }
        return "\(max(1, Int(ceil(seconds / 60))))m"
    }
}
