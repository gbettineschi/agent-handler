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
    private var epochs: [String: (owner: String, epoch: UUID)] = [:]
    private var generation = UUID()
    private var known = 0
    private var deliveries: [UUID: Task<DeliveryOutcome, Never>] = [:]
    public init(directory: URL, controller: RequestController) {
        self.directory = directory; self.controller = controller
        stream = DesktopStream(dataDirectory: directory)
        installation = "codex-desktop:" + RecordCoding.hash([directory.standardizedFileURL.path])
    }
    public func start(threadIDs: Set<String>) {
        wanted = Set(threadIDs.sorted().prefix(16))
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
        generation = UUID(); task?.cancel(); task = nil; stream.stop(); wanted = []; known = 0
        for delivery in deliveries.values { delivery.cancel() }
        let previous = epochs; epochs = [:]
        for thread in previous.keys { _ = await controller.begin(scope: scope(thread)) }
    }
    public func health() -> Health {
        .init(followed: wanted.count, known: known, message: wanted.isEmpty ? "No conversations selected" :
              known == 0 ? "Desktop unavailable or incompatible — use the source app" : "Observing \(known) Desktop conversations · questions only")
    }
    private func scope(_ thread: String) -> RequestScope { .init(installation: installation, conversation: thread) }
    private func reconcile(token: UUID) async {
        guard token == generation else { return }
        let threads = stream.threads
        known = 0
        for (thread, entry) in epochs where threads[thread] == nil || !wanted.contains(thread) {
            await controller.invalidate(scope: scope(thread), epoch: entry.epoch)
            guard token == generation else { return }
            epochs.removeValue(forKey: thread)
        }
        for threadID in wanted.sorted() {
            guard let thread = threads[threadID] else { continue }
            let epoch: UUID
            if let current = epochs[threadID], current.owner == thread.ownerClientID { epoch = current.epoch }
            else {
                epoch = await controller.begin(scope: scope(threadID))
                guard token == generation else { await controller.invalidate(scope: scope(threadID), epoch: epoch); return }
                epochs[threadID] = (thread.ownerClientID, epoch)
            }
            do {
                let requests = try DesktopQuestions.parse(state: thread.state, threadID: threadID, owner: thread.ownerClientID, installation: installation)
                guard token == generation else { return }
                await controller.observe(.init(scope: scope(threadID), epoch: epoch, revision: thread.revision, requests: requests))
                known += 1
            } catch { await controller.invalidate(scope: scope(threadID), epoch: epoch) }
            guard token == generation else { return }
        }
    }
    public func deliver(_ attempt: ResponseAttempt) async -> DeliveryOutcome {
        guard attempt.request.key.scope.installation == installation, !Task.isCancelled else { return .notSent }
        let directory = directory, stream = stream, installation = installation
        let delivery = Task.detached(priority: .userInitiated) { () -> DeliveryOutcome in
            var wrote = false
            do {
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
