import SwiftUI
import AppKit
import AgentHandlerCore

struct HandlerPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: PanelPresentation
    let collapse: () -> Void
    @State private var drafts: [String: QuestionDraft] = [:]
    @Environment(\.colorSchemeContrast) private var contrast

    private var expanded: Bool { presentation.expanded }
    private var current: RequestView? { model.displayedRequest }
    private var indicator: String {
        if model.issue != nil || model.needsSourceApproval || model.trackingWarning != nil ||
            model.requests.contains(where: { $0.state != .pending && $0.state != .sending }) {
            return "exclamationmark.triangle.fill"
        }
        return !model.requests.isEmpty ? "exclamationmark.bubble.fill" : model.menuBarState.working > 0 ? "ellipsis.circle" : "circle.dotted"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Divider()
                if let issue = model.issue {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text(issue).font(.callout)
                            Spacer(minLength: 0)
                            PanelIconButton(title: "Dismiss message", symbol: "xmark") { model.issue = nil }
                        }.padding(12).background(.orange.opacity(0.10))
                }
                if model.needsSourceApproval && model.enabled {
                    Label("Some approvals need the source app.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                if let warning = model.trackingWarning, model.enabled {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.showSettings {
                    HandlerSettingsView(model: model).padding(16)
                } else {
                    if let current, !model.showSessions {
                        requestNavigation(current)
                        SingleRequestView(view: current, draft: draft(for: current.request),
                                          answer: { model.respond(current.request, answer: $0) })
                            .id(current.request.fingerprint)
                    } else if !model.sessions.isEmpty {
                        SessionsView(sessions: model.sessions, now: model.sessionClock, dismiss: model.dismissSession) { key in
                            model.selectedRequestID = key
                            model.showSessions = false
                        }
                    } else { emptyState }
                    if let dismissal = model.dismissal, model.showSessions {
                        HStack(spacing: 8) {
                            Text("Hidden: \(dismissal.session.title)").lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary).help(dismissal.session.title)
                            Spacer(minLength: 4)
                            Button("Undo", action: model.undoDismissal)
                                .buttonStyle(.borderless).keyboardShortcut("z", modifiers: .command)
                                .help("Restore this finished session (⌘Z)")
                        }.font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
                            .overlay(alignment: .top) { Divider() }
                    }
                    if model.demo { footer }
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.55 : 0.16), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: model.requests.map { $0.request.fingerprint }) { _, fingerprints in
            let live = Set(fingerprints)
            drafts = drafts.filter { live.contains($0.key) }
            if let selected = model.selectedRequestID, !model.requests.contains(where: { $0.id == selected }) {
                model.selectedRequestID = nil
                model.showSessions = true
            }
        }
        .onChange(of: model.demoScenario) { _, _ in model.showSessions = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: indicator)
                .foregroundStyle(model.requests.isEmpty && model.issue == nil && !model.needsSourceApproval ? Color.secondary : .orange)
                .accessibilityHidden(true)
            Text(model.showSettings ? "Settings" : "Agent Handler")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if model.demo { Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            if expanded {
                if !model.hiddenSessions.isEmpty {
                    Menu {
                        ForEach(model.hiddenSessions) { session in
                            Button(session.title) { model.restoreSession(session) }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 12))
                            .frame(width: 28, height: 28)
                    }.menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Restore hidden sessions").help("Restore a hidden finished session")
                }
                if !model.requests.isEmpty {
                    Text("\(model.requests.count)").monospacedDigit().font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange).help("Requests needing attention; the menu-bar number also includes working and recently finished sessions.").accessibilityLabel("\(model.requests.count) \(model.requests.count == 1 ? "request needs" : "requests need") attention")
                }
                PanelIconButton(title: model.showSettings ? (model.showSessions ? "Back to sessions" : "Back to question") : "Settings", symbol: model.showSettings ? "arrow.left" : "gearshape") {
                    model.showSettings.toggle()
                }.keyboardShortcut(",", modifiers: .command)
                PanelIconButton(title: "Close panel (Escape)", symbol: "xmark", action: collapse)
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(.horizontal, expanded ? 16 : 12).frame(height: expanded ? 46 : 30)
    }

    private func requestNavigation(_ current: RequestView) -> some View {
        HStack(spacing: 8) {
            PanelIconButton(title: "All sessions", symbol: "chevron.left") { model.showSessions = true }
            Text(model.titles[current.id.scope.conversation] ?? "Desktop conversation")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .help(model.titles[current.id.scope.conversation] ?? current.id.scope.conversation)
            Spacer(minLength: 0)
            if model.requests.count > 1 {
                Menu {
                    ForEach(Array(model.requests.enumerated()), id: \.element.id) { index, request in
                        Button {
                            model.selectedRequestID = request.id
                        } label: {
                            if current.id == request.id {
                                Label("\(index + 1). \(request.request.title.components(separatedBy: .newlines).first ?? "Request")", systemImage: "checkmark")
                            } else {
                                Text("\(index + 1). \(request.request.title.components(separatedBy: .newlines).first ?? "Request")")
                            }
                        }
                    }
                } label: {
                    Text("\((model.requests.firstIndex { $0.id == current.id } ?? 0) + 1) of \(model.requests.count)").monospacedDigit()
                }.menuStyle(.borderlessButton).fixedSize().font(.caption).accessibilityLabel("Choose request")
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: !model.enabled ? "pause.circle" : model.connectedConversations == 0 && !model.demo ? "desktopcomputer" : "tray")
                .font(.system(size: 25, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(!model.enabled ? "Tracking is paused" : model.needsSourceApproval ? "Check Desktop for approvals" : model.connectedConversations == 0 && !model.demo ? "Waiting for Desktop" : "No sessions to show").font(.headline)
            Text(model.connectedConversations == 0 && !model.demo ? "Open a local Work conversation to connect. Check Settings if it stays unavailable." : "New activity will appear automatically.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "desktopcomputer")
            Text("Demo · no agent connection")
                .lineLimit(1)
            Spacer(minLength: 0)
                Menu("Examples") {
                    ForEach(DemoScenario.allCases) { scenario in
                        Button(scenario.title) { Task { await model.loadDemo(scenario) } }
                    }
                    Divider()
                    Button("Reset example") { Task { await model.loadDemo() } }
                }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Demo examples")
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
    }

    private func draft(for request: AttentionRequest) -> Binding<QuestionDraft> {
        Binding(get: { drafts[request.fingerprint] ?? QuestionDraft() }, set: { drafts[request.fingerprint] = $0 })
    }
}

private struct SingleRequestView: View {
    let view: RequestView
    @Binding var draft: QuestionDraft
    let answer: (UserAnswer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if view.state != .pending {
                Label(status, systemImage: view.state == .sending ? "arrow.up.circle" : "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch view.request.content {
                    case .question(let options, let allowsText):
                        let paragraphs = view.request.title.components(separatedBy: "\n\n")
                        Text(paragraphs.first ?? view.request.title).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if paragraphs.count > 1 {
                            Text(paragraphs.dropFirst().joined(separator: "\n\n")).font(.system(size: 13))
                                .foregroundStyle(.secondary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(options, id: \.id) { option in
                            Button { draft.select(option.id) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: draft.choice == option.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(draft.choice == option.id ? Color.accentColor : .secondary)
                                    Text(option.label).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(RequestActionStyle(selected: draft.choice == option.id)).handlerFocusRing().disabled(view.state != .pending)
                                .accessibilityAddTraits(draft.choice == option.id ? [.isSelected] : [])
                        }
                        if allowsText {
                            TextField(options.isEmpty ? "Your answer" : "Or write an answer", text: Binding(get: { draft.text }, set: { draft.write($0) }), axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(2...6).disabled(view.state != .pending)
                                .accessibilityLabel("Your answer")
                            if draft.text.utf8.count > 16_384 {
                                Label("Answer is too long", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    case .approval:
                        let paragraphs = view.request.title.components(separatedBy: "\n\n")
                        Text(paragraphs.first ?? view.request.title).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                        if paragraphs.count > 1 {
                            Text(paragraphs.dropFirst().joined(separator: "\n\n"))
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 16)
            }.scrollBounceBehavior(.basedOnSize).scrollIndicators(.visible)
            Divider()
            switch view.request.content {
            case .question(let options, let allowsText):
                HStack {
                    Text("⌘↵ to send").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Command Return to send")
                    Spacer()
                    Button(view.state == .sending ? "Sending…" : "Send answer") {
                        if let value = draft.answer(options: options, allowsText: allowsText) { answer(value) }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.return, modifiers: .command).help("Send answer (⌘Return)")
                        .disabled(view.state != .pending || draft.answer(options: options, allowsText: allowsText) == nil)
                }.padding(16)
            case .approval(let choices):
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(choices, id: \.id) { choice in
                            Button { answer(.decision(choice.id)) } label: {
                                Text(choice.label).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(RequestActionStyle()).handlerFocusRing().disabled(view.state != .pending)
                        }
                    }.padding(16)
                }.scrollBounceBehavior(.basedOnSize).frame(maxHeight: 180)
            }
        }
    }
    private var status: String {
        switch view.state {
        case .sending: "Sending to the source app…"
        case .uncertain: "Delivery is uncertain. Check the source app. This answer will not be sent again."
        case .unavailable, .rejected: "Source unavailable. Continue in the source app."
        default: "Request ended."
        }
    }
}

/// macOS's bordered push-button bezel truncates multiline labels. Keep the
/// native Button semantics while giving each exact permission scope room to wrap.
private struct RequestActionStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(configuration.isPressed ? 0.18 : selected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .white.opacity(contrast == .increased ? 0.55 : 0.14), lineWidth: selected ? 1.5 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.45)
    }
}
