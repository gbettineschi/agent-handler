import AppKit
import SwiftUI
import ServiceManagement
import AgentHandlerCore
import CodexDesktopAdapter
import ClaudeDesktopAdapter

@MainActor final class AppModel: ObservableObject {
    @Published var requests: [RequestView] = []
    @Published var activities: [ActivityView] = []
    @Published var claudeActivities: [ActivityView] = []
    @Published var titles: [String: String] = [:]
    @Published var health = "Starting…"
    @Published var connectedConversations = 0
    @Published var selectedConversations = 0
    @Published var connectionChecked = false
    @Published var needsSourceApproval = false
    @Published var trackingWarning: String?
    @Published var issue: String?
    @Published var showSettings = false
    @Published var selectedRequestID: RequestKey?
    @Published var showSessions = true
    @Published var demoScenario: DemoScenario = .questions
    @Published var recentConversationIDs: [String] = []
    @Published private(set) var dismissal: SessionDismissal?
    @Published private(set) var sessionClock = Date()
    private var lifecycle = SessionLifecycle()
    private var presentationTimer: Task<Void, Never>?
    private var savedLifecycle: Data?
    private var observedSessions: [SessionSummary] {
        SessionSummary.rows(activities: activities + claudeActivities, requests: requests, titles: titles, recentIDs: recentConversationIDs)
    }
    var hiddenSessions: [SessionSummary] { lifecycle.hidden(observedSessions) }
    var sessions: [SessionSummary] { lifecycle.visible(observedSessions) }
    var menuBarState: MenuBarState {
        MenuBarState(sessions: sessions, now: sessionClock, enabled: enabled,
                     warning: issue != nil || trackingWarning != nil || needsSourceApproval)
    }
    func updateSessionPresentation(now: Date = Date()) {
        lifecycle.observe(observedSessions, now: now)
        if let dismissal, !dismissal.canUndo(in: observedSessions, now: now) { self.dismissal = nil }
        sessionClock = now
        persistLifecycle()
        attentionChanged?()
    }
    func dismissSession(_ session: SessionSummary) {
        guard session.isFinished else { return }
        lifecycle.dismiss(session)
        dismissal = SessionDismissal(session: session, now: Date())
        sessionClock = Date()
        persistLifecycle()
        attentionChanged?()
    }
    func restoreSession(_ session: SessionSummary) {
        guard observedSessions.contains(where: { $0.id == session.id && $0.turnID == session.turnID && $0.isFinished }),
              lifecycle.restoreDismissed(session) else { return }
        if dismissal?.session.id == session.id, dismissal?.session.turnID == session.turnID { dismissal = nil }
        sessionClock = Date()
        persistLifecycle()
        attentionChanged?()
    }
    func undoDismissal() {
        defer { dismissal = nil }
        guard let dismissal, dismissal.canUndo(in: observedSessions, now: Date()) else { return }
        lifecycle.restoreDismissed(dismissal.session)
        sessionClock = Date()
        persistLifecycle()
        attentionChanged?()
    }
    private func persistLifecycle() {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard !demo, let data = try? encoder.encode(lifecycle), data != savedLifecycle else { return }
        UserDefaults.standard.set(data, forKey: "sessionPresentation.v1")
        savedLifecycle = data
    }
    var displayedRequest: RequestView? { requests.first { $0.id == selectedRequestID } ?? SessionSummary.preferredRequest(requests) }
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "desktopEnabled"); Task { await reconfigure() } } }
    @Published var extraThreads: String { didSet { UserDefaults.standard.set(extraThreads, forKey: "extraThreads"); lastDiscovery = 0 } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let demo: Bool
    let core: RequestController
    private let adapter: DesktopAdapter
    private let claude = ClaudeDesktopObserver()
    private let directory: URL
    private let instanceLock: InstanceLock
    private var watching: Task<Void, Never>?
    private var refreshing: Task<Void, Never>?
    private var observingClaude: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    private var sleeping = false
    private var lastDiscovery: TimeInterval = 0
    private var metadataSignature = ""
    private var refreshingDiscovery = false
    private var discoveryWarning: String?
    private var demoGeneration = UUID()
    private var ownerTitles: [String: String] = [:]
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
        extraThreads = UserDefaults.standard.string(forKey: "extraThreads") ?? ""
    }

    func start() {
        if !demo, let data = UserDefaults.standard.data(forKey: "sessionPresentation.v1"),
           let restored = try? JSONDecoder().decode(SessionLifecycle.self, from: data) {
            lifecycle = restored; savedLifecycle = data
        }
        presentationTimer = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateSessionPresentation()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        watching = Task { [weak self, core] in
            for await views in await core.updates() {
                guard let self, !Task.isCancelled else { return }
                requests = views.filter(\.needsAttention)
                updateSessionPresentation()
            }
        }
        if demo { Task { await loadDemo() }; return }
        refreshing = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDiscovery()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        observingClaude = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if enabled, !sleeping {
                    let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first
                    let source = app.map { "\($0.processIdentifier):\($0.launchDate?.timeIntervalSince1970 ?? 0)" }
                    await claude.poll(sourceInstance: source)
                    claudeActivities = await claude.activity()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }; self.sleeping = true
                await self.adapter.stop(); await self.claude.stop()
                self.activities = await self.adapter.activity(); self.claudeActivities = await self.claude.activity()
                self.connectedConversations = 0; self.connectionChecked = false
                self.health = "Paused during sleep"
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.sleeping = false; self.lastDiscovery = 0; await self.refreshDiscovery() }
        })
    }

    private func reconfigure() async {
        guard !demo else { return }
        await adapter.stop(); await claude.stop()
        activities = await adapter.activity(); claudeActivities = await claude.activity(); lastDiscovery = 0
        connectedConversations = 0; connectionChecked = false
        needsSourceApproval = false
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
            case .success(let values):
                candidates = values; titles = Dictionary(values.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
                    .merging(ownerTitles, uniquingKeysWith: { _, native in native })
                recentConversationIDs = values.map(\.id)
                discoveryWarning = nil
            case .failure:
                candidates = []; discoveryWarning = "Conversation discovery unavailable; add thread IDs in Settings"
            }
            let pinned = requests.map { $0.id.scope.conversation }
            let explicit = extraThreads.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.utf8.count <= 256 }
            var selected: [String] = []
            for id in pinned + explicit + candidates.map(\.id) where !selected.contains(id) && selected.count < 16 { selected.append(id) }
            lifecycle.establishBaseline(conversations: Set(selected + candidates.map(\.id)))
            await adapter.start(threadIDs: Set(selected))
        }
        let state = await adapter.health()
        trackingWarning = discoveryWarning
        connectedConversations = state.known; selectedConversations = state.followed; connectionChecked = true
        needsSourceApproval = state.needsSourceApproval
        activities = await adapter.activity()
        ownerTitles.merge(await adapter.conversationTitles(), uniquingKeysWith: { _, native in native })
        let retained = Set(recentConversationIDs + activities.map { $0.id.conversation } + requests.map { $0.id.scope.conversation })
        ownerTitles = ownerTitles.filter { retained.contains($0.key) }
        titles.merge(ownerTitles, uniquingKeysWith: { _, native in native })
        health = [discoveryWarning, state.message, await claude.health()].compactMap { $0 }.joined(separator: "\n")
        updateSessionPresentation()
        if await core.persistenceFailed { issue = "Responses disabled: delivery tracking is unavailable. Use the source app." }
    }

    func respond(_ request: AttentionRequest, answer: UserAnswer) {
        Task {
            do { try await core.respond(key: request.key, fingerprint: request.fingerprint, answer: answer,
                                        using: demo ? DemoTransport() : adapter) }
            catch { issue = "This request changed or cannot be answered here. Refresh it in the source app." }
        }
    }
    func loadDemo(_ scenario: DemoScenario? = nil) async {
        guard demo else { return }
        lifecycle = SessionLifecycle(); dismissal = nil
        let generation = UUID(); demoGeneration = generation
        if let scenario { demoScenario = scenario }
        let scenario = demoScenario
        let scope = RequestScope(installation: "demo", conversation: "Demo conversation"), turn = UUID().uuidString
        let epoch = await core.begin(scope: scope)
        guard demoGeneration == generation else { return }
        let questions = scenario.requests(scope: scope, turn: turn)
        await core.observe(.init(scope: scope, epoch: epoch, revision: 1, requests: questions))
        guard demoGeneration == generation else { return }
        selectedRequestID = questions.first?.key
        issue = nil
        if scenario == .unavailable { await core.invalidate(scope: scope, epoch: epoch) }
        if scenario == .uncertain, let first = questions.first {
            try? await core.respond(key: first.key, fingerprint: first.fingerprint, answer: .decision("accept"), using: DemoTransport(outcome: .uncertain))
        }
        guard demoGeneration == generation else { return }
        health = "DEMO · synthetic requests, no agent connection"
        titles[scope.conversation] = "Agent Handler interface test"
        var demoActivity = ActivityStore()
        for (conversation, phase) in [(scope.conversation, ActivityPhase.running), ("demo-earlier", .completed), ("demo-other", .failed)] {
            let activityScope = RequestScope(installation: "demo", conversation: conversation)
            let activityEpoch = demoActivity.begin(scope: activityScope)
            demoActivity.observe(.init(scope: activityScope, epoch: activityEpoch, revision: 1, turnID: "demo-turn", phase: phase, attention: .clear))
        }
        activities = demoActivity.views
        titles["demo-earlier"] = "Review the latest changes"
        titles["demo-other"] = "Run the optional integration check"
        recentConversationIDs = [scope.conversation, "demo-earlier", "demo-other"]
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { issue = "Launch at login is unavailable for this development build." }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}

private struct DisabledLedger: DeliveryLedger {
    struct Unavailable: Error {}
    func reserve(key: RequestKey, fingerprint: String, attemptID: UUID) throws { throw Unavailable() }
    func finish(key: RequestKey, attemptID: UUID, outcome: DeliveryOutcome) throws { throw Unavailable() }
    func status(for key: RequestKey) throws -> LedgerEntry? { throw Unavailable() }
    func close(key: RequestKey) throws { throw Unavailable() }
}
