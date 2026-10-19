import Foundation
import Testing
@testable import CodexDesktopAdapter

struct DesktopSocketTests {
    @Test func fragmentedFramesAndInterleavedBroadcasts() throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let wire = try DesktopIPC(path: server.directory.appendingPathComponent("ipc/ipc.sock").path, timeout: 2)
        defer { wire.close() }
        let response = try wire.request(method: "initialize", version: 0, source: "initializing-client", params: ["clientType": "agent-handler"])
        #expect((response["result"] as? [String: Any])?["clientId"] as? String == "fixture-client")
        let state = try wire.conversationState(source: "fixture-client", owner: "desktop-owner", threadID: "thread")
        #expect(state["turns"].arrayValue?.count == 1)
        wire.close() // Double close is deliberately harmless.
    }
    @Test func unknownStreamVersionIsRejected() throws {
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState()), streamVersion: 12); defer { server.stop() }
        let wire = try DesktopIPC(path: server.directory.appendingPathComponent("ipc/ipc.sock").path, timeout: 2)
        defer { wire.close() }
        #expect(throws: (any Error).self) { _ = try wire.conversationState(source: "fixture-client", owner: "desktop-owner", threadID: "thread") }
    }
    @Test func incomingFrameLimitAndMissingSocket() throws {
        #expect(throws: (any Error).self) { _ = try DesktopIPC(path: "/private/tmp/agent-handler-no-such-socket-" + UUID().uuidString, timeout: 0.1) }
        let server = try FixtureDesktopServer(state: JSONValue.parse(fixtureState())); defer { server.stop() }
        let wire = try DesktopIPC(path: server.directory.appendingPathComponent("ipc/ipc.sock").path, timeout: 2)
        defer { wire.close() }
        try wire.follow(true, source: "fixture-client", owner: "desktop-owner", threadID: "thread")
        #expect(throws: (any Error).self) { _ = try wire.message(limit: 8) }
    }
}
