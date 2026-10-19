import AppKit
import SwiftUI
import ServiceManagement
import AgentHandlerCore
import CodexDesktopAdapter

@MainActor final class AppModel: ObservableObject {
    @Published var requests: [RequestView] = []
    @Published var titles: [String: String] = [:]
    @Published var health = "Starting…"
    @Published var issue: String?
    @Published var showSettings = false
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "desktopEnabled"); Task { await reconfigure() } } }
    @Published var displayID: String { didSet { UserDefaults.standard.set(displayID, forKey: "displayID"); placementChanged?() } }
    @Published var extraThreads: String { didSet { UserDefaults.standard.set(extraThreads, forKey: "extraThreads"); lastDiscovery = 0 } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let demo: Bool
    let core: RequestController
    private let adapter: DesktopAdapter
    private let directory: URL
    private let instanceLock: InstanceLock
    private var watching: Task<Void, Never>?
    private var refreshing: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    private var sleeping = false
    private var lastDiscovery: TimeInterval = 0
    private var metadataSignature = ""
    private var refreshingDiscovery = false
    var placementChanged: (() -> Void)?
    var attentionChanged: (() -> Void)?

    init(demo: Bool) throws {
        self.demo = demo
        let storage = demo
            ? FileManager.default.temporaryDirectory.appendingPathComponent("agent-handler-demo-\(getuid())")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentHandler")
        instanceLock = try InstanceLock(url: storage.appendingPathComponent("instance.lock"))
        directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
        let ledger: any DeliveryLedger
        if demo { ledger = MemoryLedger() }
        else {
            do { ledger = try SQLiteLedger(url: storage.appendingPathComponent("delivery.sqlite")) }
            catch { ledger = DisabledLedger(); issue = "Responses disabled: the delivery ledger could not be opened." }
        }
        core = RequestController(ledger: ledger)
        adapter = DesktopAdapter(directory: directory, controller: core)
        enabled = UserDefaults.standard.object(forKey: "desktopEnabled") as? Bool ?? true
        displayID = UserDefaults.standard.string(forKey: "displayID") ?? "automatic"
        extraThreads = UserDefaults.standard.string(forKey: "extraThreads") ?? ""
    }

    func start() {
        watching = Task { [weak self, core] in
            for await views in await core.updates() {
                guard let self, !Task.isCancelled else { return }
                requests = views.filter(\.needsAttention)
                attentionChanged?()
            }
        }
        if demo { Task { await loadDemo() }; return }
        refreshing = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDiscovery()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.sleeping = true; await self.adapter.stop(); self.health = "Paused during sleep" }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.sleeping = false; self.lastDiscovery = 0; await self.refreshDiscovery() }
        })
    }

    private func reconfigure() async {
        guard !demo else { return }
        await adapter.stop(); lastDiscovery = 0
        await refreshDiscovery()
    }
    private func refreshDiscovery() async {
        guard !demo, !sleeping, !refreshingDiscovery else { return }
        guard enabled else { health = "Desktop connection disabled"; return }
        refreshingDiscovery = true; defer { refreshingDiscovery = false }
        let signature = ["state_5.sqlite", "state_5.sqlite-wal"].map { name in
            let attrs = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            return "\(attrs?[.modificationDate] ?? "missing"):\(attrs?[.size] ?? 0)"
        }.joined(separator: "|")
        let now = ProcessInfo.processInfo.systemUptime
        if signature != metadataSignature || now - lastDiscovery >= 60 || lastDiscovery == 0 {
            lastDiscovery = now; metadataSignature = signature
            let directory = directory
            let result = await Task.detached(priority: .utility) { Result { try ThreadDiscovery.candidates(directory: directory) } }.value
            guard enabled, !sleeping else { return }
            let candidates: [ThreadCandidate]
            switch result {
            case .success(let values): candidates = values; titles = Dictionary(values.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            case .failure: candidates = []; health = "Conversation discovery unavailable; add thread IDs in Settings"
            }
            let pinned = requests.map { $0.id.scope.conversation }
            let explicit = extraThreads.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.utf8.count <= 256 }
            var selected: [String] = []
            for id in pinned + explicit + candidates.map(\.id) where !selected.contains(id) && selected.count < 16 { selected.append(id) }
            await adapter.start(threadIDs: Set(selected))
        }
        let state = await adapter.health()
        health = state.message
        if await core.persistenceFailed { issue = "Responses disabled: delivery tracking is unavailable. Use the source app." }
    }

    func respond(_ request: AttentionRequest, answer: UserAnswer) {
        Task {
            do { try await core.respond(key: request.key, fingerprint: request.fingerprint, answer: answer,
                                        using: demo ? DemoTransport() : adapter) }
            catch { issue = "This request changed or cannot be answered here. Refresh it in the source app." }
        }
    }
    func loadDemo() async {
        let scope = RequestScope(installation: "demo", conversation: "Demo conversation"), turn = UUID().uuidString
        let epoch = await core.begin(scope: scope)
        let questions = [
            AttentionRequest(key: .init(scope: scope, turn: turn, nativeID: .string("first")), owner: "demo", title: "Which option should I use?",
                             content: .question(options: [.init(id: "simple", label: "Keep it simple"), .init(id: "details", label: "Show the details")], allowsText: true)),
            AttentionRequest(key: .init(scope: scope, turn: turn, nativeID: .string("second")), owner: "demo", title: "Anything else I should consider?", content: .question(options: [], allowsText: true))
        ]
        await core.observe(.init(scope: scope, epoch: epoch, revision: 1, requests: questions))
        health = "DEMO · synthetic requests, no agent connection"
    }
    func openSource() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else { issue = "ChatGPT/Codex Desktop could not be found."; return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { issue = "Launch at login is unavailable for this development build." }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

private struct DemoTransport: ResponseTransport {
    func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome { .accepted }
}
private struct DisabledLedger: DeliveryLedger {
    struct Unavailable: Error {}
    func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws { throw Unavailable() }
    func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws { throw Unavailable() }
    func status(for key: RequestKey) throws -> LedgerEntry? { throw Unavailable() }
    func close(key: RequestKey) throws { throw Unavailable() }
}
