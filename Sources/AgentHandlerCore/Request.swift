import Foundation
import CryptoKit

public enum NativeID: Hashable, Codable, Sendable { case string(String), integer(Int64) }
public struct RequestScope: Hashable, Codable, Sendable {
    public let installation: String
    public let conversation: String
    public init(installation: String, conversation: String) { self.installation = installation; self.conversation = conversation }
}
public struct RequestKey: Hashable, Codable, Sendable {
    public let scope: RequestScope
    public let turn: String?
    public let nativeID: NativeID
    public init(scope: RequestScope, turn: String?, nativeID: NativeID) { self.scope = scope; self.turn = turn; self.nativeID = nativeID }
    public var digest: String { stableDigest(self) }
}
public struct ResponseOption: Equatable, Codable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}
public enum RequestContent: Equatable, Codable, Sendable {
    case question(options: [ResponseOption], allowsText: Bool)
    case approval(choices: [ResponseOption])
}
public struct AttentionRequest: Equatable, Codable, Sendable {
    public let key: RequestKey
    public let owner: String
    public let title: String
    public let content: RequestContent
    public let sourceFingerprint: String?
    public init(key: RequestKey, owner: String, title: String, content: RequestContent, sourceFingerprint: String? = nil) {
        self.key = key; self.owner = owner; self.title = title; self.content = content; self.sourceFingerprint = sourceFingerprint
    }
    public var fingerprint: String { stableDigest(self) }
    var isValid: Bool {
        let options: [ResponseOption]
        switch content {
        case .question(let values, let text):
            guard text || !values.isEmpty else { return false }; options = values
        case .approval(let values): guard !values.isEmpty else { return false }; options = values
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf8.count <= 16_384
            && !owner.isEmpty && !key.scope.installation.isEmpty && !key.scope.conversation.isEmpty
            && options.count <= 128 && Set(options.map(\.id)).count == options.count
            && options.allSatisfy { !$0.id.isEmpty && !$0.label.isEmpty && $0.label.utf8.count <= 16_384 }
    }
}
public struct RequestSnapshot: Sendable {
    public let scope: RequestScope
    public let epoch: UUID
    public let revision: Int64
    public let requests: [AttentionRequest]
    public init(scope: RequestScope, epoch: UUID, revision: Int64, requests: [AttentionRequest]) {
        self.scope = scope; self.epoch = epoch; self.revision = revision; self.requests = requests
    }
}
public enum RequestState: String, Codable, Sendable { case pending, unavailable, sending, accepted, uncertain, closed, rejected }
public struct RequestView: Identifiable, Equatable, Sendable {
    public var id: RequestKey { request.key }
    public let request: AttentionRequest
    public internal(set) var state: RequestState
    public var needsAttention: Bool { state != .accepted && state != .closed }
}
func stableDigest<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // The domain contains only finite, non-throwing encodable value types.
    let bytes = try! encoder.encode(value)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
