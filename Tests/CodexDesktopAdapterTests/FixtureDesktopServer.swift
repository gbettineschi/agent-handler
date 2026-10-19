// Adapted from Agent HUD Open, Apache-2.0. See THIRD_PARTY_NOTICES.md.
import Darwin
import Foundation
@testable import CodexDesktopAdapter

/// A fixture hub. It answers only fixture-owned requests and never connects to Desktop's live socket.
/// As Desktop's owner does, it sends a follower the whole state once and what changes after that.
final class FixtureDesktopServer: @unchecked Sendable {
    let directory = URL(fileURLWithPath: "/private/tmp/agent-handler-fixture-\(UUID().uuidString.prefix(8))")
    private let listener: Int32
    private let lock = NSLock()
    private let sending = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var stopped = false
    private var peers: Set<Int32> = []
    private var followers: [Int32: Set<String>] = [:]
    private var fixtureState: JSONValue
    private var fixtureOwner: String? = "desktop-owner"
    private var fixtureRevision: Int64 = 1
    private let discoveryCondition = NSCondition()
    private var discoveryPaused = false
    func pauseDiscoveryResponses() { discoveryCondition.withLock { discoveryPaused = true } }
    func resumeDiscoveryResponses() {
        discoveryCondition.withLock { discoveryPaused = false; discoveryCondition.broadcast() }
    }
    private let acknowledges: Bool
    private let dropAnswer: Bool
    private let streamVersion: Int64
    private let fragmentSize: Int
    private var received: [JSONValue] = []
    /// Setting the state sends it whole to whoever follows, as a new revision.
    var state: JSONValue {
        get { lock.withLock { fixtureState } }
        set {
            let targets = lock.withLock { () -> [(Int32, String)] in
                fixtureState = newValue
                fixtureRevision += 1
                return followers.flatMap { peer, threads in threads.map { (peer, $0) } }
            }
            for (peer, thread) in targets { try? send(peer, snapshot(thread)) }
        }
    }
    var owner: String? {
        get { lock.withLock { fixtureOwner } }
        set { lock.withLock { fixtureOwner = newValue } }
    }
    var revision: Int64 { lock.withLock { fixtureRevision } }
    var methods: [String] { lock.withLock { received.compactMap { $0["method"].stringValue } } }
    var answers: [JSONValue] {
        lock.withLock { received.filter {
            ["thread-follower-submit-mcp-server-elicitation-response", "thread-follower-steer-turn"].contains($0["method"].stringValue ?? "")
        } }
    }
    /// How many times a thread was asked for: followed, or followed again for its whole state.
    var follows: Int {
        lock.withLock { received.filter {
            $0["method"].stringValue == "thread-stream-following-changed" && $0["params"]["following"].boolValue == true
        }.count }
    }

    var unfollows: Int {
        lock.withLock { received.filter {
            $0["method"].stringValue == "thread-stream-following-changed" && $0["params"]["following"].boolValue == false
        }.count }
    }

    func emitSnapshot(_ state: JSONValue, thread: String, revision: Int64) {
        let targets = lock.withLock { followers.filter { $0.value.contains(thread) }.map(\.key) }
        for peer in targets {
            try? send(peer, .object([
                "type": .string("broadcast"), "method": .string("thread-stream-state-changed"), "version": .integer(streamVersion),
                "sourceClientId": owner.map(JSONValue.string) ?? .null,
                "params": .object(["hostId": .string("local"), "conversationId": .string(thread),
                    "change": .object(["type": .string("snapshot"), "revision": .integer(revision), "conversationState": state])])
            ]))
        }
    }

    /// Sends followers one of the hub's own announcements.
    func announce(_ method: String, _ params: [String: JSONValue]) {
        let targets = lock.withLock { Array(followers.keys) }
        for peer in targets {
            try? send(peer, .object(["type": .string("broadcast"), "method": .string(method), "version": .integer(1),
                                     "sourceClientId": .string("hub"), "params": .object(params)]))
        }
    }

    init(state: JSONValue, acknowledges: Bool = true, dropAnswer: Bool = false, streamVersion: Int64 = 11, fragmentSize: Int = 3) throws {
        fixtureState = state
        self.acknowledges = acknowledges
        self.dropAnswer = dropAnswer
        self.streamVersion = streamVersion
        self.fragmentSize = max(1, fragmentSize)
        let folder = directory.appendingPathComponent("ipc")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("ipc.sock").path
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, FixtureSocket.fits(path) else { throw FixtureFailure.socket }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { field in
            field.withMemoryRebound(to: CChar.self, capacity: 104) { strlcpy($0, path, 104) }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 8) == 0 else {
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: directory)
            throw FixtureFailure.socket
        }
        // This loop blocks for the fixture's lifetime. Give it a dedicated thread so parallel
        // fixtures cannot occupy every worker of a small CI runner's shared dispatch pool.
        Thread.detachNewThread { self.serve(); self.finished.signal() }
    }

    func stop() {
        resumeDiscoveryResponses()
        let active = lock.withLock { () -> Set<Int32> in stopped = true; return peers }
        for peer in active { Darwin.shutdown(peer, SHUT_RDWR) }
        Darwin.close(listener)
        _ = finished.wait(timeout: .now() + 2)
        try? FileManager.default.removeItem(at: directory)
    }

    /// Sends followers a change as patches. The change is the test's to describe: the fixture's own state is not
    /// touched, and `base` can name a revision the follower does not hold. `late` sends a change of an earlier
    /// revision, as one that was on its way when the state was sent, and leaves the fixture's revision where it is.
    func change(_ patches: [JSONValue], base: Int64? = nil, late: Int64? = nil) {
        let (targets, from, to, owner) = lock.withLock { () -> ([(Int32, String)], Int64, Int64, String?) in
            let from = base ?? fixtureRevision
            if late == nil { fixtureRevision += 1 }
            return (followers.flatMap { peer, threads in threads.map { (peer, $0) } }, from, late ?? fixtureRevision, fixtureOwner)
        }
        for (peer, thread) in targets {
            try? send(peer, .object([
                "type": .string("broadcast"), "method": .string("thread-stream-state-changed"), "version": .integer(streamVersion),
                "sourceClientId": owner.map(JSONValue.string) ?? .null, "params": .object([
                    "hostId": .string("local"), "conversationId": .string(thread),
                    "change": .object(["type": .string("patches"), "baseRevision": .integer(from), "revision": .integer(to),
                                       "patches": .array(patches)]),
                ]),
            ]))
        }
    }

    private func snapshot(_ thread: String) -> JSONValue {
        let (state, revision, owner) = lock.withLock { (fixtureState, fixtureRevision, fixtureOwner) }
        return .object([
            "type": .string("broadcast"), "method": .string("thread-stream-state-changed"), "version": .integer(streamVersion),
            "sourceClientId": owner.map(JSONValue.string) ?? .null, "params": .object([
                "hostId": .string("local"), "conversationId": .string(thread),
                "change": .object(["type": .string("snapshot"), "revision": .integer(revision), "conversationState": state]),
            ]),
        ])
    }

    private func serve() {
        while !lock.withLock({ stopped }) {
            var entry = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&entry, 1, 100) > 0, entry.revents & Int16(POLLIN) != 0 else { continue }
            let connection = Darwin.accept(listener, nil, nil)
            guard connection >= 0 else { return }
            lock.withLock { _ = peers.insert(connection) }
            var on: Int32 = 1
            setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            // A stream stays connected while an answer comes and goes on a connection of its own.
            Thread.detachNewThread { [self] in
                do { while true { try handle(receive(connection), peer: connection) } } catch { }
                lock.withLock { peers.remove(connection); followers.removeValue(forKey: connection) }
                Darwin.close(connection)
            }
        }
    }

    private func handle(_ message: JSONValue, peer: Int32) throws {
        lock.withLock { received.append(message) }
        let method = message["method"].stringValue ?? ""
        if method == "thread-stream-following-changed" {
            guard let thread = message["params"]["conversationId"].stringValue else { return }
            if message["params"]["following"].boolValue == true, owner != nil {
                lock.withLock { _ = followers[peer, default: []].insert(thread) }
                try send(peer, snapshot(thread))
            } else {
                lock.withLock { _ = followers[peer]?.remove(thread) }
            }
            return
        }
        var reply: [String: JSONValue] = ["type": .string("response"), "requestId": message["requestId"], "resultType": .string("success")]
        switch method {
        case "initialize":
            try send(peer, .object(["type": .string("broadcast"), "method": .string("unrelated-event")]))
            reply["result"] = .object(["clientId": .string("fixture-client")])
        case "thread-owner-discovery":
            try waitForDiscoveryRelease()
            if let owner {
                reply["handledByClientId"] = .string(owner)
                reply["result"] = .object([:])
            } else {
                reply["resultType"] = .string("error")
                reply["error"] = .string("no-client-found")
            }
        case "thread-follower-submit-mcp-server-elicitation-response":
            reply["handledByClientId"] = owner.map(JSONValue.string) ?? .null
            reply["result"] = .object(["method": .string(method), "result": .object(["ok": .bool(acknowledges)])])
        case "thread-follower-steer-turn":
            if dropAnswer { throw FixtureFailure.socket }
            reply["handledByClientId"] = owner.map(JSONValue.string) ?? .null
            reply["result"] = .object(["method": .string(method), "result": .object([
                "result": .object(["turnId": .string(acknowledges ? "native-turn" : "different-turn")]),
            ])])
        default: throw FixtureFailure.protocolError
        }
        try send(peer, .object(reply))
    }

    private func waitForDiscoveryRelease() throws {
        discoveryCondition.lock()
        defer { discoveryCondition.unlock() }
        let deadline = Date().addingTimeInterval(5)
        while discoveryPaused {
            guard discoveryCondition.wait(until: deadline) else { throw FixtureFailure.socket }
        }
    }

    private func send(_ peer: Int32, _ message: JSONValue) throws {
        let payload = try RecordCoding.encoder().encode(message)
        var length = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        // A reply and a change can be sent from two threads; a frame is never cut by another.
        guard sending.withLock({ FixtureSocket.send(peer, frame, fragmentSize: fragmentSize) }) else { throw FixtureFailure.socket }
    }

    private func receive(_ peer: Int32) throws -> JSONValue {
        let header = try read(peer, count: 4)
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length > 0, length <= 1024 * 1024 else { throw FixtureFailure.protocolError }
        return try JSONValue.parse(read(peer, count: Int(length)))
    }

    private func read(_ peer: Int32, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            var bytes = [UInt8](repeating: 0, count: min(count - result.count, 4096))
            let size = Darwin.recv(peer, &bytes, bytes.count, 0)
            if size < 0, errno == EINTR { continue }
            guard size > 0 else { throw FixtureFailure.socket }
            result.append(contentsOf: bytes.prefix(size))
        }
        return result
    }

    private enum FixtureFailure: Error { case socket, protocolError }
}

enum FixtureSocket {
    static func fits(_ path: String) -> Bool { path.utf8.count < 104 }
    static func send(_ fd: Int32, _ bytes: Data, fragmentSize: Int = 3) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!.advanced(by: offset), min(fragmentSize, bytes.count - offset), 0) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
}
