import Foundation
import AgentHandlerCore

struct SessionOrdering: Codable, Equatable {
    private struct Record: Codable, Equatable {
        var scope: RequestScope
        var recent: UInt64
        var attention: UInt64
        var waiting: Bool
        var requests: [RequestKey]
        var humanInputID: String?
        var inputBaseline: Bool
        var resolutionAccounted = false
        var accountedApprovals: Set<RequestKey> = []
    }
    private var records: [Record] = []
    private var sequence: UInt64 = 0
    private mutating func next() -> UInt64 {
        if sequence < .max { sequence += 1 }
        return sequence
    }
    private static func sessionScope(_ scope: RequestScope) -> RequestScope {
        guard scope.installation.hasSuffix(":approvals") else { return scope }
        return .init(installation: String(scope.installation.dropLast(":approvals".count)), conversation: scope.conversation)
    }
    private static func needsIntervention(_ session: SessionSummary) -> Bool {
        session.hasUnresolvedInput
    }
    /// Metadata is only the initial seed. Running hints, ticks and unknown gaps never promote a row.
    mutating func observe(_ sessions: [SessionSummary], requests: [RequestView] = [], newlyFinished: [SessionSummary] = []) {
        let byScope = Dictionary(grouping: requests.filter(\.needsAttention), by: { Self.sessionScope($0.id.scope) })
        let finished = Set(newlyFinished.map(\.id))
        for session in sessions.reversed() {
            let keys = Set((byScope[session.id] ?? []).map(\.id) + [session.request?.id].compactMap { $0 })
            let waiting = Self.needsIntervention(session)
            guard let index = records.firstIndex(where: { $0.scope == session.id }) else {
                let ordinal = next()
                records.append(.init(scope: session.id, recent: ordinal, attention: ordinal,
                    waiting: waiting, requests: keys.sorted { $0.digest < $1.digest }, humanInputID: session.humanInputID,
                    inputBaseline: session.status != .unknown || session.humanInputID != nil))
                continue
            }
            var record = records[index]
            let fresh = keys.subtracting(record.requests)
            if !fresh.isEmpty || (waiting && !record.waiting) {
                record.attention = next(); record.resolutionAccounted = false
            }
            var interacted = false
            if let input = session.humanInputID {
                interacted = record.inputBaseline && record.humanInputID != input
                record.humanInputID = input
            }
            if session.status != .unknown { record.inputBaseline = true }
            if interacted, record.waiting || waiting { record.resolutionAccounted = true }
            if session.status != .unknown || session.request != nil {
                if waiting {
                    // Missing keys during independent activity/request hydration cannot resolve input.
                    // Remember recent keys plus every currently visible key through the whole wait.
                    record.requests += fresh.sorted { $0.digest < $1.digest }
                    record.requests = Array(record.requests.suffix(512))
                    for key in keys where !record.requests.contains(key) { record.requests.insert(key, at: 0) }
                    record.accountedApprovals.formIntersection(record.requests)
                } else {
                    interacted = interacted || (record.waiting && !record.resolutionAccounted)
                    record.requests = []; record.resolutionAccounted = false; record.accountedApprovals = []
                }
                record.waiting = waiting
            }
            if interacted || finished.contains(session.id) { record.recent = next() }
            records[index] = record
        }
        if records.count > 256 {
            let current = Set(sessions.map(\.id))
            records = Array((records.filter { current.contains($0.scope) } + records.filter { !current.contains($0.scope) }.sorted { $0.recent > $1.recent }).prefix(256))
        }
    }
    mutating func humanIntervened(in scope: RequestScope, requestKey: RequestKey? = nil) {
        guard let index = records.firstIndex(where: { $0.scope == Self.sessionScope(scope) }) else { return }
        records[index].recent = next()
        if records[index].waiting { records[index].resolutionAccounted = true }
        if let requestKey, records[index].requests.contains(requestKey) {
            records[index].accountedApprovals.insert(requestKey)
        }
    }
    /// Typed controller withdrawal only, never inferred from an absent/hydrating key.
    /// This affects recency, not whether a decision was accepted or executed.
    mutating func approvalsClosed(_ keys: [RequestKey]) {
        for key in keys {
            guard let index = records.firstIndex(where: { $0.scope == Self.sessionScope(key.scope) }),
                  records[index].requests.contains(key),
                  records[index].accountedApprovals.insert(key).inserted else { continue }
            records[index].recent = next()
            records[index].resolutionAccounted = true
        }
    }
    func sorted(_ sessions: [SessionSummary]) -> [SessionSummary] {
        let byScope = Dictionary(uniqueKeysWithValues: records.map { ($0.scope, $0) })
        return sessions.sorted {
            let lhs = Self.needsIntervention($0), rhs = Self.needsIntervention($1)
            if lhs != rhs { return lhs }
            let left = lhs ? byScope[$0.id]?.attention : byScope[$0.id]?.recent
            let right = rhs ? byScope[$1.id]?.attention : byScope[$1.id]?.recent
            if left != right { return (left ?? 0) > (right ?? 0) }
            return ($0.id.installation, $0.id.conversation) < ($1.id.installation, $1.id.conversation)
        }
    }
}
