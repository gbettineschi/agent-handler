import Foundation

public actor RequestController {
    var store = RequestStore()
    let ledger: any DeliveryLedger
    private var listeners: [UUID: AsyncStream<[RequestView]>.Continuation] = [:]
    public private(set) var persistenceFailed = false
    public init(ledger: any DeliveryLedger) { self.ledger = ledger }
    public func begin(scope: RequestScope) -> UUID { let epoch = store.begin(scope: scope); publish(); return epoch }
    public func observe(_ snapshot: RequestSnapshot) {
        let before = store.views.filter { $0.id.scope == snapshot.scope && $0.needsAttention }
        guard store.apply(snapshot: snapshot) else { publish(); return }
        do {
            for old in before where !snapshot.requests.contains(where: { $0.key == old.id }) { try ledger.close(key: old.id) }
            for request in snapshot.requests {
                guard let entry = try ledger.status(for: request.key) else { continue }
                let state: RequestState?
                switch entry.status {
                case .accepted: state = entry.fingerprint == request.fingerprint ? .accepted : .uncertain
                case .closed: state = entry.fingerprint == request.fingerprint ? .closed : .uncertain
                case .inFlight: state = store.records[request.key]?.view.state == .sending ? .sending : .uncertain
                case .uncertain: state = .uncertain
                case .notSent, .rejected: state = nil
                }
                if let state { store.records[request.key]?.view.state = state }
            }
        } catch { disableResponses() }
        publish()
    }
    public func invalidate(scope: RequestScope, epoch: UUID) { store.invalidate(scope: scope, epoch: epoch); publish() }
    public func snapshot() -> [RequestView] { store.views }
    public func updates() -> AsyncStream<[RequestView]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[RequestView]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        listeners[id] = continuation
        continuation.yield(store.views)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeListener(id) } }
        return stream
    }
    private func removeListener(_ id: UUID) { listeners.removeValue(forKey: id) }
    private func publish() { for continuation in listeners.values { continuation.yield(store.views) } }
    private func disableResponses() {
        persistenceFailed = true
        for key in store.records.keys where store.records[key]?.view.state == .pending { store.records[key]?.view.state = .unavailable }
    }
    public func respond(key: RequestKey, fingerprint: String, answer: UserAnswer, using transport: any ResponseTransport) async throws {
        guard !persistenceFailed else { throw ResponseError.persistenceUnavailable }
        guard !Task.isCancelled, let record = store.records[key], store.isFresh(key),
              record.view.state == .pending, record.view.request.fingerprint == fingerprint else { throw ResponseError.stale }
        guard record.view.request.allows(answer) else { throw ResponseError.unsupported }
        let attempt = ResponseAttempt(id: UUID(), request: record.view.request, epoch: record.epoch, answer: answer)
        do { try ledger.reserve(key: key, fingerprint: fingerprint, attemptID: attempt.id) }
        catch let error as ResponseError { throw error }
        catch { disableResponses(); publish(); throw ResponseError.persistenceUnavailable }
        store.records[key]?.view.state = .sending
        publish()
        let outcome = await transport.deliver(attempt)
        var actual = outcome
        do { try ledger.finish(key: key, attemptID: attempt.id, outcome: outcome) }
        catch { actual = .uncertain; disableResponses() }
        // A receipt for a previous owner, epoch or request body cannot settle its replacement.
        if let current = store.records[key], current.epoch == attempt.epoch,
           current.view.request.fingerprint == fingerprint, current.view.state == .sending {
            switch actual {
            case .accepted: store.records[key]?.view.state = .accepted
            case .uncertain: store.records[key]?.view.state = .uncertain
            case .notSent, .rejected:
                store.records[key]?.view.state = .rejected
                store.invalidate(scope: key.scope, epoch: attempt.epoch)
            }
        }
        publish()
    }
}

extension AttentionRequest {
    func allows(_ answer: UserAnswer) -> Bool {
        switch (content, answer) {
        case (.question(_, let allowed), .text(let value)):
            return allowed && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 16_384
        case (.question(let choices, _), .option(let id)), (.approval(let choices), .decision(let id)):
            return choices.contains { $0.id == id }
        default: return false
        }
    }
}
