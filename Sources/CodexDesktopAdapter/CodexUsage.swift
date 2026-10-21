import Foundation

/// Account metadata only. This never participates in request/response authority.
public struct CodexUsageSnapshot: Sendable {
    public struct Window: Sendable, Equatable {
        public let remainingPercent: Int
        public let durationMinutes: Int?
        public let resetsAt: Date?
    }
    public let windows: [Window]
    public let fetchedAt: Date

    public static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> Self {
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        let bucket = reply.rateLimitsByLimitId?["codex"] ?? reply.rateLimits.flatMap {
            $0.limitId == nil || $0.limitId == "codex" ? $0 : nil
        }
        let windows = [bucket?.primary, bucket?.secondary].compactMap { window -> Window? in
            guard let window, let used = window.usedPercent, used.isFinite else { return nil }
            return Window(remainingPercent: Int((100 - min(100, max(0, used))).rounded(.down)),
                          durationMinutes: window.windowDurationMins.flatMap { $0 > 0 ? $0 : nil },
                          resetsAt: window.resetsAt.flatMap { (1...253_402_300_799).contains($0) ? Date(timeIntervalSince1970: $0) : nil })
        }
        return Self(windows: windows, fetchedAt: fetchedAt)
    }
    /// Never claim a refreshed allowance by extrapolating beyond a reset boundary.
    public func displayWindow(at now: Date) -> Window? {
        guard (0...180).contains(now.timeIntervalSince(fetchedAt)),
              !windows.contains(where: { $0.resetsAt.map { $0 <= now } ?? false }) else { return nil }
        return windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    private struct Reply: Decodable {
        var rateLimits: Bucket?
        var rateLimitsByLimitId: [String: Bucket]?
    }
    private struct Bucket: Decodable {
        var limitId: String?
        var primary: NativeWindow?
        var secondary: NativeWindow?
    }
    private struct NativeWindow: Decodable {
        var usedPercent: Double?
        var windowDurationMins: Int?
        var resetsAt: Double?
    }
}
