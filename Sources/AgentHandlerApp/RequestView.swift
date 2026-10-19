import SwiftUI
import AppKit
import AgentHandlerCore

struct HandlerPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: PanelPresentation
    let toggle: () -> Void
    let collapse: () -> Void
    @State private var drafts: [String: QuestionDraft] = [:]
    @Environment(\.colorSchemeContrast) private var contrast

    private var expanded: Bool { presentation.expanded }
    private var current: RequestView? { model.displayedRequest }
    private var working: Int { model.activities.filter { $0.status == .running }.count }
    private var summary: String {
        if !model.requests.isEmpty { return "\(model.requests.count) \(model.requests.count == 1 ? "needs" : "need") you" }
        if !model.enabled { return "Paused" }
        if model.needsSourceApproval || model.trackingWarning != nil || model.issue != nil { return "Check Desktop" }
        if !model.demo && model.connectionChecked && model.selectedConversations > 0 && model.connectedConversations == 0 { return "Desktop unavailable" }
        if working > 0 { return "\(working) working" }
        return "Agent Handler"
    }
    private var indicator: String {
        !model.requests.isEmpty ? "exclamationmark.bubble.fill" : working > 0 ? "ellipsis.circle" : "circle.dotted"
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
                            Button { model.issue = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
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
                    if let current {
                        requestNavigation(current)
                        SingleRequestView(view: current, draft: draft(for: current.request),
                                          answer: { model.respond(current.request, answer: $0) })
                            .id(current.request.fingerprint)
                    } else { emptyState }
                    footer
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 20 : 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: expanded ? 20 : 15, style: .continuous)
                .strokeBorder(.white.opacity(contrast == .increased ? 0.55 : 0.16), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .onChange(of: model.requests.map { $0.request.fingerprint }) { _, fingerprints in
            let live = Set(fingerprints)
            drafts = drafts.filter { live.contains($0.key) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: indicator)
                        .foregroundStyle(model.requests.isEmpty ? Color.secondary : .orange)
                    Text(expanded ? (model.showSettings ? "Settings" : "Agent Handler") : summary)
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if model.demo { Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                    if !expanded { Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse Agent Handler" : "Expand Agent Handler, \(summary)")
                .help(expanded ? "Collapse panel" : "Show questions and approvals")
            if expanded {
                if !model.requests.isEmpty {
                    Text("\(model.requests.count)").monospacedDigit().font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3).background(.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange).accessibilityLabel("\(model.requests.count) \(model.requests.count == 1 ? "request needs" : "requests need") attention")
                }
                Button { model.showSettings.toggle() } label: { Image(systemName: model.showSettings ? "arrow.left" : "gearshape") }
                    .buttonStyle(.plain).frame(width: 24, height: 24)
                    .accessibilityLabel(model.showSettings ? "Back to requests" : "Settings")
                    .help(model.showSettings ? "Back to requests" : "Settings")
                Button(action: collapse) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).frame(width: 24, height: 24)
                    .accessibilityLabel("Close panel").help("Collapse panel (Escape)")
                    .keyboardShortcut(.cancelAction)
            }
        }.padding(.horizontal, expanded ? 16 : 12).frame(height: expanded ? 46 : 30)
    }

    private func requestNavigation(_ current: RequestView) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.secondary)
            Text(model.titles[current.id.scope.conversation] ?? "Desktop conversation")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .help(model.titles[current.id.scope.conversation] ?? current.id.scope.conversation)
            Spacer(minLength: 0)
            if model.requests.count > 1 {
                Menu {
                    ForEach(Array(model.requests.enumerated()), id: \.element.id) { index, request in
                        Button("\(index + 1). \(request.request.title.components(separatedBy: .newlines).first ?? "Request")") {
                            model.selectedRequestID = request.id
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
            Image(systemName: model.enabled ? "checkmark.circle" : "pause.circle")
                .font(.system(size: 25, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(!model.enabled ? "Tracking is paused" : model.needsSourceApproval ? "Check Desktop for approvals" : model.connectedConversations == 0 && !model.demo ? "Waiting for Desktop" : "No requests waiting here").font(.headline)
            Text(working > 0 ? "\(working) Desktop conversation\(working == 1 ? " is" : "s are") working." : model.connectedConversations == 0 && !model.demo ? "Open a local Work conversation to connect. Check Details if it stays unavailable." : "Questions and supported approvals appear here.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "desktopcomputer")
            Text(connectionSummary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.demo { Button("Reset demo") { Task { await model.loadDemo() } }.buttonStyle(.plain) }
            else { Button("Details") { model.showSettings = true }.buttonStyle(.plain).help("Connection details and settings") }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
    }

    private func draft(for request: AttentionRequest) -> Binding<QuestionDraft> {
        Binding(get: { drafts[request.fingerprint] ?? QuestionDraft() }, set: { drafts[request.fingerprint] = $0 })
    }
    private var connectionSummary: String {
        if model.demo { return "Demo · no agent connection" }
        if !model.enabled { return "Tracking paused" }
        if !model.connectionChecked { return "Connecting to Desktop…" }
        if model.selectedConversations == 0 { return "No Work conversations selected" }
        if model.connectedConversations == 0 { return "Desktop unavailable · check Details" }
        if model.connectedConversations < model.selectedConversations {
            return "\(model.connectedConversations) of \(model.selectedConversations) conversations connected"
        }
        return "\(model.connectedConversations) Desktop conversations connected"
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
                        Text(view.request.title).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(options, id: \.id) { option in
                            Button { draft.select(option.id) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: draft.choice == option.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(draft.choice == option.id ? Color.accentColor : .secondary)
                                    Text(option.label).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(draft.choice == option.id ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 10))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(view.state != .pending)
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
            }.scrollBounceBehavior(.basedOnSize)
            Divider()
            switch view.request.content {
            case .question(let options, let allowsText):
                HStack {
                    Text("Review before sending").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(view.state == .sending ? "Sending…" : "Send answer") {
                        if let value = draft.answer(options: options, allowsText: allowsText) { answer(value) }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(view.state != .pending || draft.answer(options: options, allowsText: allowsText) == nil)
                }.padding(16)
            case .approval(let choices):
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(choices, id: \.id) { choice in
                            Button { answer(.decision(choice.id)) } label: {
                                Text(choice.label).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(RequestActionStyle()).disabled(view.state != .pending)
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
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.10)) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(enabled ? 1 : 0.45)
    }
}
