import Foundation
import AgentHandlerCore

/// Presentation only. Never changes provider subscriptions, request authority or delivery.
struct SessionLifecycle: Codable {
    static let finishedLifetime: TimeInterval = 300
    private struct Record: Codable {
        var scope: RequestScope
        var turn: String?
        var active: Bool
        var terminalObserved: Bool
        var finishedAt: Date?
        var expiresAt: Date?
        var dismissed = false
        var unresolvedSourceInput: Bool? = nil
    }
    private var records: [Record] = []
    private var seenThisRun: Set<RequestScope> = []
    private var launchConversations: Set<String>?
    private enum CodingKeys: String, CodingKey { case records }
    mutating func establishBaseline(conversations: Set<String>) {
        if launchConversations == nil { launchConversations = conversations }
    }

    /// Returns terminal transitions observed this run, never launch history.
    @discardableResult mutating func observe(_ sessions: [SessionSummary], now: Date) -> [SessionSummary] {
        var newlyFinished: [SessionSummary] = []
        for session in sessions {
            let firstThisRun = seenThisRun.insert(session.id).inserted
            let newlyDiscovered = launchConversations.map { !$0.contains(session.id.conversation) } ?? false
            let active = session.status == .running || session.status == .needsInput || session.request != nil
            guard let index = records.firstIndex(where: { $0.scope == session.id }) else {
                records.append(.init(scope: session.id, turn: session.turnID, active: active, terminalObserved: session.isFinished,
                    finishedAt: session.isFinished && newlyDiscovered ? now : nil,
                    expiresAt: session.isFinished ? now.addingTimeInterval(Self.finishedLifetime) : nil,
                    unresolvedSourceInput: session.hasObservedSourceWait))
                continue
            }
            let previous = records[index]
            var record = previous
            if let turn = session.turnID, turn != record.turn {
                record = .init(scope: session.id, turn: turn, active: active, terminalObserved: session.isFinished,
                    finishedAt: session.isFinished && (!firstThisRun || newlyDiscovered) ? now : nil,
                    expiresAt: session.isFinished ? now.addingTimeInterval(Self.finishedLifetime) : nil)
            } else if active {
                record.active = true; record.terminalObserved = false
                record.finishedAt = nil; record.expiresAt = nil; record.dismissed = false
            } else if session.isFinished && !record.terminalObserved {
                record.finishedAt = record.active && (!firstThisRun || newlyDiscovered) ? now : nil
                record.active = false; record.terminalObserved = true
            }
            // Also migrates older saved records. A known finish deadline never restarts.
            if session.isFinished, record.expiresAt == nil {
                record.expiresAt = (record.finishedAt ?? now).addingTimeInterval(Self.finishedLifetime)
            }
            // Only an observed source-only wait is remembered here. Typed
            // requests already have their own authoritative controller state.
            if session.status == .unknown {
                record.unresolvedSourceInput = previous.unresolvedSourceInput == true || session.hasObservedSourceWait
            } else {
                record.unresolvedSourceInput = session.hasObservedSourceWait
            }
            if !firstThisRun, session.isFinished, record.finishedAt != nil, record.finishedAt != previous.finishedAt {
                newlyFinished.append(session)
            }
            records[index] = record
        }
        if records.count > 256 {
            let current = Set(sessions.map(\.id))
            records = Array((records.filter { current.contains($0.scope) } + records.filter { !current.contains($0.scope) }).prefix(256))
        }
        return newlyFinished
    }
    mutating func dismiss(_ session: SessionSummary) {
        guard session.isFinished, session.request == nil,
              let index = records.firstIndex(where: { $0.scope == session.id && $0.turn == session.turnID }) else { return }
        records[index].dismissed = true
    }
    @discardableResult mutating func restoreDismissed(_ session: SessionSummary, now: Date = Date()) -> Bool {
        guard session.isFinished,
              let index = records.firstIndex(where: { $0.scope == session.id && $0.turn == session.turnID && $0.dismissed }),
              records[index].expiresAt.map({ $0 > now }) ?? true else { return false }
        records[index].dismissed = false
        return true
    }
    func hidden(_ sessions: [SessionSummary], now: Date = Date()) -> [SessionSummary] {
        sessions.filter { session in
            session.isFinished && records.contains {
                $0.scope == session.id && $0.turn == session.turnID && $0.dismissed && ($0.expiresAt.map { $0 > now } ?? true)
            }
        }
    }
    func visible(_ sessions: [SessionSummary], now: Date = Date()) -> [SessionSummary] {
        sessions.compactMap { session in
            // Availability is not completion. Keep observing, but do not fill
            // the list with stale ordinary sessions. Actual input stays visible.
            let record = records.first(where: {
                $0.scope == session.id && ($0.turn == session.turnID || (session.status == .unknown && session.turnID == nil))
            })
            guard session.status != .unknown || session.hasUnresolvedInput || record?.unresolvedSourceInput == true else { return nil }
            guard let record else { return session }
            if session.isFinished && (record.dismissed || (record.expiresAt.map { $0 <= now } ?? false)) { return nil }
            var result = session
            if session.status == .unknown, record.unresolvedSourceInput == true { result.hasUnresolvedSourceInput = true }
            result.recentUntil = session.isFinished ? record.finishedAt?.addingTimeInterval(Self.finishedLifetime) : nil
            result.expiresAt = session.isFinished ? record.expiresAt : nil
            return result
        }
    }
}

struct MenuBarState {
    enum Mode { case idle, working, attention, recent, failed, unavailable, paused }
    let count: Int
    let working: Int
    let needsInput: Int
    let recent: Int
    let mode: Mode
    init(sessions: [SessionSummary], now: Date, enabled: Bool = true, warning: Bool = false) {
        working = sessions.filter { $0.status == .running }.count
        needsInput = sessions.filter(\.hasUnresolvedInput).count
        recent = sessions.filter { $0.isFinished && ($0.recentUntil.map { $0 > now } ?? false) }.count
        count = sessions.filter { $0.status == .running || $0.hasUnresolvedInput || ($0.isFinished && ($0.recentUntil.map { $0 > now } ?? false)) }.count
        if !enabled { mode = .paused }
        else if needsInput > 0 { mode = .attention }
        else if warning || sessions.contains(where: { $0.status == .unknown }) { mode = .unavailable }
        else if working > 0 { mode = .working }
        else if sessions.contains(where: { $0.status == .failed }) { mode = .failed }
        else if recent > 0 { mode = .recent }
        else { mode = .idle }
    }
    func shouldAnimate(reduceMotion: Bool) -> Bool { working > 0 && mode != .paused && !reduceMotion }
    var description: String {
        let prefix: String
        switch mode {
        case .paused: prefix = "Tracking paused"
        case .attention: prefix = "Needs attention"
        case .unavailable: prefix = "Some source state is unavailable"
        case .failed: prefix = "A session failed"
        default: prefix = "Agent Handler"
        }
        return "\(prefix). \(working) working, \(needsInput) need input, \(recent) finished in the last five minutes."
    }
}

struct SessionDismissal {
    let session: SessionSummary
    let expiresAt: Date
    init(session: SessionSummary, now: Date) {
        self.session = session; expiresAt = now.addingTimeInterval(10)
    }
    func canUndo(in sessions: [SessionSummary], now: Date) -> Bool {
        now < expiresAt && sessions.contains { $0.id == session.id && $0.turnID == session.turnID && $0.isFinished }
    }
}
