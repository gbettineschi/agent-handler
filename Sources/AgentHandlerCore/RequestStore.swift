import Foundation

public struct RequestStore: Sendable {
    struct ScopeState: Sendable { var epoch: UUID; var revision: Int64 = -1; var known = false }
    struct Record: Sendable { var view: RequestView; var epoch: UUID }
    var scopes: [RequestScope: ScopeState] = [:]
    var records: [RequestKey: Record] = [:]
    public init() {}
    public var views: [RequestView] { records.values.map(\.view).sorted { $0.id.digest < $1.id.digest } }
    public mutating func begin(scope: RequestScope) -> UUID {
        if let previous = scopes[scope] { invalidate(scope: scope, epoch: previous.epoch) }
        let epoch = UUID(); scopes[scope] = ScopeState(epoch: epoch)
        return epoch
    }
    @discardableResult public mutating func apply(snapshot: RequestSnapshot) -> Bool {
        guard var source = scopes[snapshot.scope], source.epoch == snapshot.epoch,
              snapshot.revision > source.revision else { return false }
        let keys = Set(snapshot.requests.map(\.key))
        let elsewhere = records.values.filter { $0.view.needsAttention && $0.view.id.scope != snapshot.scope }.count
        guard snapshot.revision >= 0, keys.count == snapshot.requests.count,
              snapshot.requests.allSatisfy({ $0.key.scope == snapshot.scope && $0.isValid }),
              snapshot.requests.count + elsewhere <= 128 else {
            invalidate(scope: snapshot.scope, epoch: snapshot.epoch)
            return false
        }
        for key in records.keys where key.scope == snapshot.scope && !keys.contains(key) {
            if records[key]?.view.state != .accepted { records[key]?.view.state = .closed }
        }
        for request in snapshot.requests {
            let previous = records[request.key]
            let same = previous?.view.request.fingerprint == request.fingerprint
            let priorState = previous?.view.state
            let state: RequestState
            if same, let priorState, [.sending, .accepted, .uncertain, .closed].contains(priorState) { state = priorState }
            else if !same, let priorState, [.sending, .uncertain, .accepted].contains(priorState) { state = .uncertain }
            else { state = .pending }
            records[request.key] = Record(view: .init(request: request, state: state), epoch: snapshot.epoch)
        }
        source.revision = snapshot.revision; source.known = true; scopes[snapshot.scope] = source
        // Terminal records are only a presentation cache; the ledger retains delivery tombstones.
        if records.count > 512 {
            for key in records.keys.sorted(by: { $0.digest < $1.digest }) where records.count > 512 {
                if records[key]?.view.needsAttention == false { records.removeValue(forKey: key) }
            }
        }
        return true
    }
    public mutating func invalidate(scope: RequestScope, epoch: UUID) {
        guard scopes[scope]?.epoch == epoch else { return }
        scopes[scope]?.known = false
        for key in records.keys where key.scope == scope {
            if [.pending, .rejected].contains(records[key]!.view.state) { records[key]?.view.state = .unavailable }
            if records[key]?.view.state == .sending { records[key]?.view.state = .uncertain }
        }
    }
    func isFresh(_ key: RequestKey) -> Bool {
        guard let record = records[key], let source = scopes[key.scope] else { return false }
        return source.known && source.epoch == record.epoch
    }
}
