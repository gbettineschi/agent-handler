import Foundation
import Testing
@testable import AgentHandlerCore

struct ApprovalDetailsTests {
    @Test func displayDetailsPreserveLegacyFingerprintAndWireChangesStillInvalidate() throws {
        struct Legacy: Encodable {
            let key: RequestKey; let owner: String; let title: String
            let content: RequestContent; let sourceFingerprint: String?
        }
        let base = AttentionRequest(key: question().key, owner: "owner", title: "Raw source prompt",
            content: .approval(choices: [.init(id: "accept", label: "Allow once")]), sourceFingerprint: "native-1")
        let details = ApprovalDetails(subject: .command(command: "printf test", directory: "/tmp", reason: "Check connection"))
        let decorated = AttentionRequest(key: base.key, owner: base.owner, title: base.title, content: base.content,
            sourceFingerprint: base.sourceFingerprint, approvalDetails: details)
        #expect(decorated.fingerprint == base.fingerprint)
        #expect(base.fingerprint == stableDigest(Legacy(key: base.key, owner: base.owner, title: base.title, content: base.content, sourceFingerprint: base.sourceFingerprint)))
        let changed = AttentionRequest(key: base.key, owner: base.owner, title: base.title, content: base.content,
            sourceFingerprint: "native-2", approvalDetails: details)
        #expect(changed.fingerprint != decorated.fingerprint)
        let oldData = try JSONEncoder().encode(Legacy(key: base.key, owner: base.owner, title: base.title, content: base.content, sourceFingerprint: base.sourceFingerprint))
        #expect(try JSONDecoder().decode(AttentionRequest.self, from: oldData).approvalDetails == nil)
        #expect(try JSONDecoder().decode(AttentionRequest.self, from: JSONEncoder().encode(decorated)) == decorated)
    }
    @Test func oversizedOrUnmatchedDisplayMetadataCannotBecomeActionable() {
        let key = question().key
        for details in [
            ApprovalDetails(subject: .command(command: String(repeating: "x", count: 33_000), directory: "/tmp", reason: nil)),
            ApprovalDetails(subject: .command(command: "printf test", directory: "/tmp", reason: nil), persistentActions: ["missing-choice": .savedPermission])
        ] {
            let request = AttentionRequest(key: key, owner: "owner", title: "Prompt", content: .approval(choices: [.init(id: "accept", label: "Allow once")]), approvalDetails: details)
            #expect(!request.isValid)
        }
    }
}
