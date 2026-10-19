import Foundation

public enum ActivityPhase: String, Sendable { case running, completed, failed, cancelled }
public enum ActivityAttention: String, Sendable { case clear, required, unknown }
public enum ActivityStatus: String, Sendable { case unknown, running, needsInput, completed, failed, cancelled }

/// A source fact, separate from request delivery. Completion never settles an answer or permission.
public struct ActivitySnapshot: Sendable {
    public let scope: RequestScope
    public let epoch: UUID
    public let revision: Int64
    public let turnID: String
    public let phase: ActivityPhase
    public let attention: ActivityAttention
    public init(scope: RequestScope, epoch: UUID, revision: Int64, turnID: String,
                phase: ActivityPhase, attention: ActivityAttention) {
        self.scope = scope; self.epoch = epoch; self.revision = revision
        self.turnID = turnID; self.phase = phase; self.attention = attention
    }
}

public struct ActivityView: Identifiable, Equatable, Sendable {
    public let id: RequestScope
    public let turnID: String
    public let phase: ActivityPhase
    public let attention: ActivityAttention
    public internal(set) var isCurrent: Bool
    public var status: ActivityStatus {
        guard isCurrent else { return .unknown }
        if attention == .required { return .needsInput }
        guard attention == .clear else { return .unknown }
        switch phase {
        case .running: return .running
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
}

/// Latest facts only: no timers, inferred completion, historical notification replay or response authority.
public struct ActivityStore: Sendable {
    private struct Source: Sendable {
        var epoch: UUID
        var revision: Int64 = -1
        var view: ActivityView?
    }
    private var sources: [RequestScope: Source] = [:]
    public init() {}
    public var views: [ActivityView] {
        sources.values.compactMap(\.view).sorted {
            ($0.id.installation, $0.id.conversation) < ($1.id.installation, $1.id.conversation)
        }
    }
    public mutating func begin(scope: RequestScope) -> UUID {
        var previous = sources[scope]?.view
        previous?.isCurrent = false
        let epoch = UUID()
        sources[scope] = Source(epoch: epoch, view: previous)
        return epoch
    }
    @discardableResult public mutating func observe(_ snapshot: ActivitySnapshot) -> Bool {
        guard var source = sources[snapshot.scope], source.epoch == snapshot.epoch,
              snapshot.revision >= 0, snapshot.revision > source.revision else { return false }
        source.revision = snapshot.revision
        guard !snapshot.scope.installation.isEmpty, !snapshot.scope.conversation.isEmpty,
              !snapshot.turnID.isEmpty, snapshot.turnID.utf8.count <= 256 else {
            source.view?.isCurrent = false; sources[snapshot.scope] = source
            return false
        }
        source.view = .init(id: snapshot.scope, turnID: snapshot.turnID, phase: snapshot.phase,
                            attention: snapshot.attention, isCurrent: true)
        sources[snapshot.scope] = source
        return true
    }
    public mutating func invalidate(scope: RequestScope, epoch: UUID) {
        guard sources[scope]?.epoch == epoch else { return }
        sources[scope]?.view?.isCurrent = false
    }
    public mutating func remove(scope: RequestScope) { sources.removeValue(forKey: scope) }
}
