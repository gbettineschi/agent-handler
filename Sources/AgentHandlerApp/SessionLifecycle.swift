import Foundation
import AgentHandlerCore

/// Presentation only. Never changes provider subscriptions, request authority or delivery.
struct SessionLifecycle: Codable {
    private struct Record: Codable {
        var scope: RequestScope
        var turn: String?
        var active: Bool
        var terminalObserved: Bool
        var finishedAt: Date?
        var dismissed = false
    }
    private var records: [Record] = []
    private var seenThisRun: Set<RequestScope> = []
    private var launchConversations: Set<String>?
    private enum CodingKeys: String, CodingKey { case records }
    mutating func establishBaseline(conversations: Set<String>) {
        if launchConversations == nil { launchConversations = conversations }
    }

    mutating func observe(_ sessions: [SessionSummary], now: Date) {
        for session in sessions {
            let firstThisRun = seenThisRun.insert(session.id).inserted
            let newlyDiscovered = launchConversations.map { !$0.contains(session.id.conversation) } ?? false
            let active = session.status == .running || session.status == .needsInput || session.request != nil
            guard let index = records.firstIndex(where: { $0.scope == session.id }) else {
                // Existing completions at launch are history, not new notifications.
                records.append(.init(scope: session.id, turn: session.turnID, active: active, terminalObserved: session.isFinished,
                                     finishedAt: session.isFinished && newlyDiscovered ? now : nil))
                continue
            }
            var record = records[index]
            if let turn = session.turnID, turn != record.turn {
                record = .init(scope: session.id, turn: turn, active: active, terminalObserved: session.isFinished,
                               finishedAt: session.isFinished && (!firstThisRun || newlyDiscovered) ? now : nil)
            } else if active {
                record.active = true; record.terminalObserved = false
                record.finishedAt = nil; record.dismissed = false
            } else if session.isFinished && !record.terminalObserved {
                record.finishedAt = record.active && (!firstThisRun || newlyDiscovered) ? now : nil
                record.active = false; record.terminalObserved = true
            }
            records[index] = record
        }
        // Retain a bounded number of dismissed turns, preferring current sessions.
        if records.count > 256 {
            let current = Set(sessions.map(\.id))
            records = Array((records.filter { current.contains($0.scope) } + records.filter { !current.contains($0.scope) }).prefix(256))
        }
    }
    mutating func dismiss(_ session: SessionSummary) {
        guard session.isFinished, session.request == nil,
              let index = records.firstIndex(where: { $0.scope == session.id && $0.turn == session.turnID }) else { return }
        records[index].dismissed = true
    }
    func visible(_ sessions: [SessionSummary]) -> [SessionSummary] {
        sessions.compactMap { session in
            guard let record = records.first(where: { $0.scope == session.id && $0.turn == session.turnID }) else { return session }
            if record.dismissed && session.isFinished && session.request == nil { return nil }
            var result = session
            result.recentUntil = session.isFinished ? record.finishedAt?.addingTimeInterval(300) : nil
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
        needsInput = sessions.filter { $0.status == .needsInput || $0.request != nil }.count
        recent = sessions.filter { $0.isFinished && ($0.recentUntil.map { $0 > now } ?? false) }.count
        count = sessions.filter { $0.status == .running || $0.status == .needsInput || $0.request != nil || ($0.isFinished && ($0.recentUntil.map { $0 > now } ?? false)) }.count
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
