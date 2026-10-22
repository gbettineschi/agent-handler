import AppKit
import SwiftUI
import ServiceManagement
import OSLog
import AgentHandlerCore
import CodexDesktopAdapter
import ClaudeDesktopAdapter

@MainActor final class AppModel: ObservableObject {
    @Published var requests: [RequestView] = []
    @Published var activities: [ActivityView] = []
    @Published var claudeActivities: [ActivityView] = []
    @Published var titles: [String: String] = [:]
    @Published var codexUsage: CodexUsageSnapshot?
    var usageHeader: UsageHeader { UsageHeader(snapshot: codexUsage, now: Date()) }
    @Published var health = "Starting…"
    @Published var connectedConversations = 0
    @Published var selectedConversations = 0
    @Published var connectionChecked = false
    @Published var needsSourceApproval = false
    @Published var observedCodexConversations: Set<String> = []
    @Published var sourceApprovalConversations: Set<String> = []
    @Published var trackingWarning: String?
    @Published var companionStyle: CompanionStyle {
        didSet { if !demo { companionStyle.save(to: .standard) } }
    }
    @Published var notchAvailable = false
    @Published var issue: String?
    @Published var showSettings = false
    @Published var selectedRequestID: RequestKey?
    @Published var showSessions = true
    @Published var demoScenario: DemoScenario = .questions
    @Published var recentConversationIDs: [String] = []
    @Published private(set) var dismissal: SessionDismissal?
    @Published private(set) var sessionClock = Date()
    private var lifecycle = SessionLifecycle()
    private var ordering = SessionOrdering()
    private var savedOrdering: SessionOrdering?
    private var presentationTimer: Task<Void, Never>?
    private var savedLifecycle: Data?
    private var observedSessions: [SessionSummary] {
        func scopes(_ ids: Set<String>) -> Set<RequestScope> {
            Set(ids.map { RequestScope(installation: adapter.installation, conversation: $0) })
        }
        return SessionSummary.rows(activities: activities + claudeActivities, requests: requests, titles: titles, recentIDs: recentConversationIDs,
            observedScopes: scopes(observedCodexConversations), sourceApprovalScopes: scopes(sourceApprovalConversations))
    }
    var hiddenSessions: [SessionSummary] { ordering.sorted(lifecycle.hidden(observedSessions, now: sessionClock)) }
    var sessions: [SessionSummary] { ordering.sorted(lifecycle.visible(observedSessions, now: sessionClock)) }
    var menuBarState: MenuBarState {
        MenuBarState(sessions: sessions, now: sessionClock, enabled: enabled,
                     warning: issue != nil || trackingWarning != nil || needsSourceApproval)
    }
    func updateSessionPresentation(now: Date = Date()) {
        let observed = observedSessions
        let newlyFinished = lifecycle.observe(observed, now: now)
        ordering.observe(observed, requests: requests, newlyFinished: newlyFinished)
        if let dismissal, !dismissal.canUndo(in: observed, now: now) ||
            !lifecycle.hidden(observed, now: now).contains(where: { $0.id == dismissal.session.id && $0.turnID == dismissal.session.turnID }) {
            self.dismissal = nil
        }
        sessionClock = now
        persistLifecycle()
        attentionChanged?()
        if let target = autoOpenPolicy.update(requests: requests, sessions: observed, newlyFinished: newlyFinished,
                                              settings: autoOpenSettings, enabled: enabled && !sleeping && !demo) {
            autoOpenRequested?(target)
        }
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
        guard !demo else { return }
        if let data = try? encoder.encode(lifecycle), data != savedLifecycle {
            UserDefaults.standard.set(data, forKey: "sessionPresentation.v1")
            savedLifecycle = data
        }
        if ordering != savedOrdering, let data = try? encoder.encode(ordering) {
            UserDefaults.standard.set(data, forKey: "sessionOrdering.v1")
            savedOrdering = ordering
        }
    }
    var displayedRequest: RequestView? { requests.first { $0.id == selectedRequestID } ?? SessionSummary.preferredRequest(requests) }
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "desktopEnabled"); Task { await reconfigure() } } }
    @Published var extraThreads: String { didSet { UserDefaults.standard.set(extraThreads, forKey: "extraThreads"); lastDiscovery = 0 } }
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var autoOpenSettings = AutoOpenSettings() {
        didSet { if !demo { autoOpenSettings.save(to: .standard) } }
    }
    private var autoOpenPolicy = AutoOpenPolicy()
    var autoOpenRequested: ((AutoOpenTarget) -> Void)?
    let demo: Bool
    let core: RequestController
    private let adapter: DesktopAdapter
    private let claude = ClaudeDesktopObserver()
    private let directory: URL
    private let instanceLock: InstanceLock
    private var watching: Task<Void, Never>?
    private var refreshing: Task<Void, Never>?
    private var observingClaude: Task<Void, Never>?
    private var refreshingUsage: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []
    private var sleeping = false
    private var lastDiscovery: TimeInterval = 0
    private var metadataSignature = ""
    private var refreshingDiscovery = false
    private var catalog = DiscoveryCatalog()
    private static let discoveryLog = Logger(subsystem: "com.agenthandler.app", category: "Discovery")
    private var demoGeneration = UUID()
    private var ownerTitles: [String: String] = [:]
    var attentionChanged: (() -> Void)?

    init(demo: Bool) throws {
        self.demo = demo
        companionStyle = CompanionStyle.load(from: .standard)
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
        if !demo { autoOpenSettings = AutoOpenSettings.load(from: .standard) }
    }

    func start() {
        if !demo, let data = UserDefaults.standard.data(forKey: "sessionPresentation.v1"),
           let restored = try? JSONDecoder().decode(SessionLifecycle.self, from: data) {
            lifecycle = restored; savedLifecycle = data
        }
        if !demo, let data = UserDefaults.standard.data(forKey: "sessionOrdering.v1"),
           let restored = try? JSONDecoder().decode(SessionOrdering.self, from: data) {
            ordering = restored; savedOrdering = restored
        }
        presentationTimer = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    if !demo, enabled, !sleeping { activities = await adapter.activity() }
                    updateSessionPresentation()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        watching = Task { [weak self, core] in
            for await views in await core.updates() {
                guard let self, !Task.isCancelled else { return }
                // Process authoritative approval withdrawal before the waiting group's keys clear.
                ordering.approvalsClosed(views.compactMap {
                    guard $0.state == .closed, case .approval = $0.request.content else { return nil }
                    return $0.id
                })
                requests = views.filter(\.needsAttention)
                updateSessionPresentation()
            }
        }
        if demo { Task { await loadDemo() }; return }
        startUsageRefresh()
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
                self.refreshingUsage?.cancel(); self.refreshingUsage = nil; self.codexUsage = nil
                await self.adapter.stop(); await self.claude.stop()
                self.activities = await self.adapter.activity(); self.claudeActivities = await self.claude.activity()
                self.connectedConversations = 0; self.connectionChecked = false
                self.health = "Paused during sleep"
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.sleeping = false; self.lastDiscovery = 0; self.startUsageRefresh(); await self.refreshDiscovery() }
        })
    }

    private func reconfigure() async {
        guard !demo else { return }
        refreshingUsage?.cancel(); refreshingUsage = nil; codexUsage = nil
        if enabled, !sleeping { startUsageRefresh() }
        await adapter.stop(); await claude.stop()
        activities = await adapter.activity(); claudeActivities = await claude.activity(); lastDiscovery = 0
        connectedConversations = 0; connectionChecked = false
        needsSourceApproval = false
        await refreshDiscovery()
    }
    private func startUsageRefresh() {
        guard !demo, enabled, !sleeping, refreshingUsage == nil else { return }
        refreshingUsage = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let bundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
                let executable = bundle?.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
                let reading: CodexUsageSnapshot?
                if let executable { reading = try? await CodexUsageReader.read(executable: executable, directory: directory) }
                else { reading = nil }
                guard !Task.isCancelled, enabled, !sleeping else { return }
                codexUsage = reading
                try? await Task.sleep(for: .seconds(60))
            }
        }
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
        if catalog.retryNeeded || signature != metadataSignature || now - lastDiscovery >= 60 || lastDiscovery == 0 {
            let directory = directory
            let result = await Task.detached(priority: .utility) { Result { try ThreadDiscovery.candidates(directory: directory) } }.value
            guard enabled, !sleeping else { return }
            let previousDiagnostic = catalog.diagnostic
            catalog.update(result)
            if let diagnostic = catalog.diagnostic, diagnostic != previousDiagnostic {
                Self.discoveryLog.error("\(diagnostic, privacy: .public)")
            } else if catalog.diagnostic == nil, previousDiagnostic != nil || lastDiscovery == 0 {
                Self.discoveryLog.notice("Conversation catalog ready: \(self.catalog.candidates.count) candidates")
            }
            let candidates = catalog.candidates
            if !catalog.retryNeeded {
                lastDiscovery = now; metadataSignature = signature
                titles = Dictionary(candidates.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
                    .merging(ownerTitles, uniquingKeysWith: { _, native in native })
                recentConversationIDs = candidates.map(\.id)
            }
            // A parser/connection failure must not evict an active session.
            // Explicit no-owner results may release ordinary stale priority.
            let pending = (await core.snapshot()).filter(\.needsAttention).map { $0.id.scope.conversation }
            guard enabled, !sleeping else { return }
            let explicit = extraThreads.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.utf8.count <= 256 }
            let candidateIDs = candidates.map(\.id)
            let baseline = Set(pending + explicit + candidateIDs).union(observedCodexConversations)
            if !catalog.retryNeeded || !baseline.isEmpty {
                lifecycle.establishBaseline(conversations: baseline)
            }
            await adapter.start(selecting: { state, currentActivities in
                Set(DiscoveryCatalog.selection(pending: pending, explicit: explicit,
                    activities: currentActivities, observed: state.observedConversations,
                    sourceOnly: state.sourceApprovalConversations, candidates: candidateIDs,
                    unowned: state.unownedConversations))
            })
        }
        let state = await adapter.health()
        trackingWarning = catalog.warning
        connectedConversations = state.known; selectedConversations = state.followed; connectionChecked = true
        needsSourceApproval = state.needsSourceApproval
        observedCodexConversations = state.observedConversations
        sourceApprovalConversations = state.sourceApprovalConversations
        activities = await adapter.activity()
        ownerTitles.merge(await adapter.conversationTitles(), uniquingKeysWith: { _, native in native })
        let retained = Set(recentConversationIDs + activities.map { $0.id.conversation } + requests.map { $0.id.scope.conversation })
            .union(observedCodexConversations).union(sourceApprovalConversations)
        ownerTitles = ownerTitles.filter { retained.contains($0.key) }
        titles.merge(ownerTitles, uniquingKeysWith: { _, native in native })
        health = [catalog.diagnostic, state.message, await claude.health()].compactMap { $0 }.joined(separator: "\n")
        updateSessionPresentation()
        if await core.persistenceFailed { issue = "Responses disabled: delivery tracking is unavailable. Use the source app." }
    }

    func respond(_ request: AttentionRequest, answer: UserAnswer) {
        // Questions acquire their accepted native input marker; don't count that echo twice.
        if case .approval = request.content {
            ordering.humanIntervened(in: request.key.scope, requestKey: request.key)
            updateSessionPresentation()
        }
        Task {
            do { try await core.respond(key: request.key, fingerprint: request.fingerprint, answer: answer,
                                        using: demo ? DemoTransport() : adapter) }
            catch { issue = "This request changed or cannot be answered here. Refresh it in the source app." }
        }
    }
    func loadDemo(_ scenario: DemoScenario? = nil) async {
        guard demo else { return }
        observedCodexConversations = []; sourceApprovalConversations = []; needsSourceApproval = false
        codexUsage = try? CodexUsageSnapshot.decode(Data("{\"rateLimits\":{\"primary\":{\"usedPercent\":29,\"windowDurationMins\":10080,\"resetsAt\":\(Date().addingTimeInterval(500_000).timeIntervalSince1970)}}}".utf8))
        lifecycle = SessionLifecycle(); ordering = SessionOrdering(); dismissal = nil; autoOpenPolicy = AutoOpenPolicy()
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
