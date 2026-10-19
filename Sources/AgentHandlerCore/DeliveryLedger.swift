import Foundation

public enum UserAnswer: Equatable, Sendable { case text(String), option(String), decision(String) }
public enum DeliveryOutcome: String, Codable, Sendable { case accepted, notSent, rejected, uncertain }
public enum LedgerStatus: String, Codable, Sendable { case inFlight, uncertain, accepted, closed, notSent, rejected }
public struct LedgerEntry: Sendable {
    public let fingerprint: String
    public let attemptID: UUID
    public let status: LedgerStatus
}
public enum ResponseError: Error, Equatable { case stale, unsupported, alreadySubmitted, persistenceUnavailable }
public struct ResponseAttempt: Sendable {
    public let id: UUID
    public let request: AttentionRequest
    public let epoch: UUID
    public let answer: UserAnswer
}
public protocol ResponseTransport: Sendable {
    func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome
}
public protocol DeliveryLedger: Sendable {
    func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws
    func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws
    func status(for key: RequestKey) throws -> LedgerEntry?
    func close(key: RequestKey) throws
}
/// Ephemeral ledger for synthetic demonstrations and tests only.
public final class MemoryLedger: DeliveryLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [RequestKey: LedgerEntry] = [:]
    public init() {}
    public func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws {
        try lock.withLock {
            if let old = entries[key], ![.notSent, .rejected].contains(old.status) { throw ResponseError.alreadySubmitted }
            entries[key] = .init(fingerprint: fingerprint, attemptID: attemptID, status: .inFlight)
        }
    }
    public func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws {
        lock.withLock {
            guard let old = entries[key], old.attemptID == attemptID else { return }
            entries[key] = .init(fingerprint: old.fingerprint, attemptID: attemptID, status: LedgerStatus(rawValue: outcome.rawValue)!)
        }
    }
    public func status(for key: RequestKey) throws -> LedgerEntry? { lock.withLock { entries[key] } }
    public func close(key: RequestKey) throws {
        lock.withLock {
            if let old = entries[key], old.status != .accepted {
                entries[key] = .init(fingerprint: old.fingerprint, attemptID: old.attemptID, status: .closed)
            }
        }
    }
}
