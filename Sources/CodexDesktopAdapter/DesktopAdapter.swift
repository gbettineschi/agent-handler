import Foundation
import AgentHandlerCore

public actor DesktopAdapter: ResponseTransport {
    public struct Health: Sendable { public let followed: Int; public let known: Int; public let message: String }
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
        for (scope, entry) in activityOwners { activityStore.invalidate(scope: scope, epoch: entry.epoch) }
        activityOwners = [:]
        for delivery in deliveries.values { delivery.cancel() }
        let previous = epochs; epochs = [:]
        for scope in previous.keys { _ = await controller.begin(scope: scope) }
    }
    public func activity() -> [ActivityView] { activityStore.views }
    public func health() -> Health {
        let message = wanted.isEmpty ? "No conversations selected" :
            known == 0 ? "Desktop unavailable or incompatible — use the source app" :
            "Observing \(known) Desktop conversations · questions and supported approvals"
        let views = activityStore.views
        let activity = views.isEmpty ? "" : " · \(views.filter { $0.status == .running }.count) running · \(views.filter { $0.status == .needsInput }.count) need input · \(views.filter { $0.status == .completed }.count) completed · \(views.filter { $0.status == .failed }.count) failed · \(views.filter { $0.status == .cancelled }.count) cancelled · \(views.filter { $0.status == .unknown }.count) unknown"
        return .init(followed: wanted.count, known: known, message: message + activity +
            (unsupportedApprovals.isEmpty ? "" : " · Approval requests need the source app"))
    }
    private func reconcile(token: UUID) async {
        guard token == generation else { return }
        let threads = stream.threads
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
                    let requests = isApproval
                        ? try DesktopApprovals.pending(state: thread.state, threadID: threadID, owner: thread.ownerClientID, installation: installation).map(\.request)
                        : try DesktopQuestions.parse(state: thread.state, threadID: threadID, owner: thread.ownerClientID, installation: installation)
                    guard token == generation else { return }
                    await controller.observe(.init(scope: source, epoch: epoch, revision: thread.revision, requests: requests))
                    if isApproval { unsupportedApprovals.remove(threadID) }
                    if !isApproval || !requests.isEmpty { recognized = true }
                } catch {
                    if isApproval { unsupportedApprovals.insert(threadID) }
                    await controller.invalidate(scope: source, epoch: epoch)
                }
                guard token == generation else { return }
            }
            if recognized { known += 1 }
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
                    turnID: value.turnID, phase: value.phase, attention: value.attention))
            } catch { activityStore.invalidate(scope: scope, epoch: epoch) }
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
