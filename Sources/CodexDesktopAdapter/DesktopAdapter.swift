import Foundation
import AgentHandlerCore

public actor DesktopAdapter: ResponseTransport {
    public struct Health: Sendable {
        public let followed: Int
        public let known: Int
        public let message: String
        public let needsSourceApproval: Bool
        /// Presentation only: a verified owner was observed, even if its history is unreadable.
        public let observedConversations: Set<String>
        public let sourceApprovalConversations: Set<String>
        /// Allocation only: explicit no-owner results, not generic connection or parser failures.
        public let unownedConversations: Set<String>
        public let diagnostics: DesktopDiagnostics
    }
    let stream: DesktopStream
    private let directory: URL
    private let controller: RequestController
    public nonisolated let installation: String
    private var task: Task<Void, Never>?
    private var wanted: Set<String> = []
    private var epochs: [RequestScope: (owner: String, epoch: UUID)] = [:]
    private var generation = UUID()
    private var known = 0
    private var unsupportedApprovals: Set<String> = []
    private var observedConversations: Set<String> = []
    private var parserIssues: [String: Set<DesktopDiagnostics.Issue>] = [:]
    private var deliveries: [UUID: Task<DeliveryOutcome, Never>] = [:]
    private var activityStore = ActivityStore()
    private var activityOwners: [RequestScope: (owner: String, epoch: UUID)] = [:]
    public init(directory: URL, controller: RequestController) {
        self.directory = directory; self.controller = controller
        stream = DesktopStream(dataDirectory: directory)
        installation = "codex-desktop:" + RecordCoding.hash([directory.standardizedFileURL.path])
    }
    public func start(threadIDs: Set<String>) {
        wanted = Set(threadIDs.sorted().prefix(16))
        observedConversations.formIntersection(wanted)
        unsupportedApprovals.formIntersection(wanted)
        parserIssues = parserIssues.filter { wanted.contains($0.key) }
        for scope in Set(activityOwners.keys).union(activityStore.views.map(\.id)) where !wanted.contains(scope.conversation) {
            activityStore.remove(scope: scope); activityOwners.removeValue(forKey: scope)
        }
        stream.follow(wanted)
        if task == nil {
            let token = generation
            task = Task { [weak self, stream] in
                for await _ in stream.changes {
                    guard !Task.isCancelled, let self else { break }
                    await self.reconcile(token: token)
                }
            }
        }
    }
    public func stop() async {
        generation = UUID(); task?.cancel(); task = nil; stream.stop(); wanted = []; known = 0; unsupportedApprovals = []
        parserIssues = [:]
        for (scope, entry) in activityOwners { activityStore.invalidate(scope: scope, epoch: entry.epoch) }
        activityOwners = [:]
        for delivery in deliveries.values { delivery.cancel() }
        let previous = epochs; epochs = [:]
        for scope in previous.keys { _ = await controller.begin(scope: scope) }
    }
    public func activity() -> [ActivityView] { activityStore.views }
    /// Select and apply without suspension so an already observed wait cannot
    /// be evicted using an older UI cache or an earlier allocation snapshot.
    /// Selection affects observation only, never request/response authority.
    @discardableResult public func start(selecting selection: @Sendable (Health, [ActivityView]) -> Set<String>) -> Set<String> {
        let selected = selection(health(), activityStore.views)
        start(threadIDs: selected)
        return wanted
    }
    /// Presentation metadata only; not an input to request identity or response authority.
    public func conversationTitles() -> [String: String] {
        var titles: [String: String] = [:]
        for (id, thread) in stream.threads where wanted.contains(id) {
            guard let value = thread.state["title"].stringValue else { continue }
            let title = String(value.prefix(512)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { titles[id] = title }
        }
        return titles
    }
    public func health() -> Health {
        let streamStatus = stream.diagnosticState
        var counts: [DesktopDiagnostics.Issue: Int] = [:]
        for issue in streamStatus.issues.values { counts[issue, default: 0] += 1 }
        for (id, issues) in parserIssues where stream.thread(id) != nil {
            for issue in issues { counts[issue, default: 0] += 1 }
        }
        let diagnostics = DesktopDiagnostics(connection: streamStatus.connection, issues: counts)
        let message = wanted.isEmpty ? "No conversations selected" : diagnostics.message(known: known)
        return .init(followed: wanted.count, known: known, message: message +
            (unsupportedApprovals.isEmpty ? "" : " · Approval requests need the source app"),
            needsSourceApproval: !unsupportedApprovals.isEmpty,
            observedConversations: observedConversations, sourceApprovalConversations: unsupportedApprovals,
            unownedConversations: streamStatus.unowned, diagnostics: diagnostics)
    }
    private func reconcile(token: UUID) async {
        guard token == generation else { return }
        let threads = stream.threads
        parserIssues = [:]
        observedConversations.formUnion(Set(threads.keys).intersection(wanted))
        reconcileActivity(threads)
        known = 0
        unsupportedApprovals = unsupportedApprovals.intersection(wanted)
        for (scope, entry) in epochs where threads[scope.conversation] == nil || !wanted.contains(scope.conversation) {
            await controller.invalidate(scope: scope, epoch: entry.epoch)
            guard token == generation else { return }
            epochs.removeValue(forKey: scope)
        }
        for threadID in wanted.sorted() {
            guard let thread = threads[threadID] else { continue }
            var recognized = false
            for isApproval in [false, true] {
                let source = RequestScope(installation: isApproval ? DesktopApprovals.installation(installation) : installation, conversation: threadID)
                let epoch: UUID
                if let current = epochs[source], current.owner == thread.ownerClientID { epoch = current.epoch }
                else {
                    epoch = await controller.begin(scope: source)
                    guard token == generation else { await controller.invalidate(scope: source, epoch: epoch); return }
                    epochs[source] = (thread.ownerClientID, epoch)
                }
                do {
                    let requests: [AttentionRequest]
                    if isApproval {
                        let pending = try DesktopApprovals.pending(state: thread.state, threadID: threadID, owner: thread.ownerClientID, installation: installation)
                        requests = pending.map(\.request)
                        if Self.hasSourceOnlyApproval(thread.state, handled: pending.map(\.wireID)) { unsupportedApprovals.insert(threadID) }
                        else { unsupportedApprovals.remove(threadID) }
                    } else {
                        requests = try DesktopQuestions.parse(state: thread.state, threadID: threadID, owner: thread.ownerClientID, installation: installation)
                    }
                    guard token == generation else { return }
                    await controller.observe(.init(scope: source, epoch: epoch, revision: thread.revision, requests: requests))
                    if !isApproval || !requests.isEmpty { recognized = true }
                } catch {
                    parserIssues[threadID, default: []].insert(isApproval ? .approvalsUnsupported : .questionsUnsupported)
                    // An unreadable queue is not evidence of an approval. Retain
                    // an existing fallback until recovery; create one only from
                    // an actual pending native approval/elicitation request.
                    if isApproval, Self.hasSourceOnlyApproval(thread.state) { unsupportedApprovals.insert(threadID) }
                    await controller.invalidate(scope: source, epoch: epoch)
                }
                guard token == generation else { return }
            }
            if recognized { known += 1 }
        }
    }
    private static func hasSourceOnlyApproval(_ state: JSONValue, handled: [JSONValue] = []) -> Bool {
        (state["requests"].arrayValue ?? []).contains {
            ["item/commandExecution/requestApproval", "mcpServer/elicitation/request"].contains($0["method"].stringValue ?? "") &&
                ($0["completed"] == .null || $0["completed"] == .bool(false)) && !handled.contains($0["id"])
        }
    }
    private func reconcileActivity(_ threads: [String: DesktopStream.Thread]) {
        for (scope, entry) in activityOwners where threads[scope.conversation] == nil {
            activityStore.invalidate(scope: scope, epoch: entry.epoch)
            activityOwners.removeValue(forKey: scope)
        }
        for threadID in wanted.sorted() {
            guard let thread = threads[threadID] else { continue }
            let scope = RequestScope(installation: installation, conversation: threadID)
            let epoch: UUID
            if let current = activityOwners[scope], current.owner == thread.ownerClientID { epoch = current.epoch }
            else {
                epoch = activityStore.begin(scope: scope)
                activityOwners[scope] = (thread.ownerClientID, epoch)
            }
            do {
                let value = try DesktopActivity.parse(state: thread.state, threadID: threadID,
                    owner: thread.ownerClientID, installation: installation)
                activityStore.observe(.init(scope: scope, epoch: epoch, revision: thread.revision,
                    turnID: value.turnID, phase: value.phase, attention: value.attention, detail: value.detail, humanInputID: value.humanInputID))
            } catch {
                parserIssues[threadID, default: []].insert(.activityUnsupported)
                activityStore.invalidate(scope: scope, epoch: epoch)
            }
        }
    }
    public func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome {
        guard [installation, DesktopApprovals.installation(installation)].contains(attempt.request.key.scope.installation), !Task.isCancelled else { return .notSent }
        let directory = directory, stream = stream, installation = installation
        let delivery = Task.detached(priority: .userInitiated) { () -> DeliveryOutcome in
            var wrote = false
            do {
                if attempt.request.key.scope.installation == DesktopApprovals.installation(installation) {
                    return try DesktopApprovals.deliver(attempt, directory: directory, stream: stream, installation: installation, didWrite: { wrote = true })
                }
                let request = attempt.request, threadID = request.key.scope.conversation
                guard request.key.turn != nil, case .string(let nativeID) = request.key.nativeID else { return .notSent }
                let wire = try DesktopIPC(path: directory.appendingPathComponent("ipc/ipc.sock").path, timeout: 10)
                defer { wire.close() }
                let initialized = try wire.request(method: "initialize", version: 0, source: "initializing-client", params: ["clientType": "agent-handler"])
                guard let client = (initialized["result"] as? [String: Any])?["clientId"] as? String, !client.isEmpty else { return .notSent }
                let discovered = try wire.request(method: "thread-owner-discovery", version: 1, source: client,
                    params: ["hostId": "local", "conversationId": threadID])
                guard discovered["handledByClientId"] as? String == request.owner,
                      let current = stream.thread(threadID), current.ownerClientID == request.owner,
                      let turnID = try DesktopQuestions.currentTurnID(current.state),
                      let turn = try DesktopQuestions.turn(turnID, in: current.state),
                      ["inProgress", "completed"].contains(turn["status"].stringValue ?? ""),
                      try DesktopQuestions.parse(state: current.state, threadID: threadID, owner: request.owner, installation: installation)
                        .contains(where: { $0 == request }) else { return .notSent }
                let answer: String
                switch (attempt.answer, request.content) {
                case (.text(let text), .question(_, let allowed)) where allowed && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= 16_384: answer = text
                case (.option(let id), .question(let choices, _)):
                    guard let choice = choices.first(where: { $0.id == id }) else { return .notSent }; answer = choice.label
                default: return .notSent
                }
                let body = try JSONSerialization.data(withJSONObject: [["questionItemId": nativeID, "question": request.title, "answer": answer]], options: [.sortedKeys, .withoutEscapingSlashes])
                let text = "<send_user_message_question_reply>\n" + String(decoding: body, as: UTF8.self) + "\n</send_user_message_question_reply>"
                let id = UUID().uuidString.lowercased()
                let startsTurn = turn["status"].stringValue == "completed"
                let method = startsTurn ? "thread-follower-start-turn" : "thread-follower-steer-turn"
                var context: [String: Any] = ["prompt": text, "turnTrigger": "send_user_message_async_question", "addedFiles": [], "fileAttachments": [], "ideContext": NSNull(), "imageAttachments": []]
                var restore: [String: Any] = ["id": id, "text": text, "createdAt": Date().timeIntervalSince1970 * 1000]
                if let cwd = current.state["cwd"].stringValue { context["workspaceRoots"] = [cwd]; restore["cwd"] = cwd }
                restore["context"] = context
                let input: [[String: Any]] = [["type": "text", "text": text, "text_elements": []]]
                let params: [String: Any]
                if startsTurn {
                    // The native owner inherits its effective settings. Never reconstruct or override
                    // permissions, model, working directory or collaboration mode in the companion.
                    params = ["conversationId": threadID, "turnStart": [
                        "request": ["threadId": threadID, "input": input, "clientUserMessageId": id,
                                    "turnTrigger": "send_user_message_async_question"],
                        "context": ["inheritThreadSettings": true, "restoreMessage": restore, "attachments": []]
                    ]]
                } else {
                    params = ["conversationId": threadID, "clientUserMessageId": id, "input": input,
                              "attachments": [], "restoreMessage": restore]
                }
                try Task.checkCancellation()
                let response = try wire.request(method: method, version: startsTurn ? 2 : 1, source: client, target: request.owner,
                    params: params, didWrite: { wrote = true })
                let receipt = try JSONValue.parse(JSONSerialization.data(withJSONObject: response))
                guard receipt["handledByClientId"].stringValue == request.owner,
                      receipt["result"]["method"].stringValue == method else { return .uncertain }
                let result = receipt["result"]["result"]["result"]
                if startsTurn {
                    guard let newTurn = result["turn"]["id"].stringValue, !newTurn.isEmpty, newTurn != turnID else { return .uncertain }
                } else {
                    guard result["turnId"].stringValue == turnID else { return .uncertain }
                }
                return .accepted
            } catch { return wrote ? .uncertain : .notSent }
        }
        deliveries[attempt.id] = delivery
        let result = await withTaskCancellationHandler(operation: { await delivery.value }, onCancel: { delivery.cancel() })
        deliveries.removeValue(forKey: attempt.id)
        return result
    }
}
