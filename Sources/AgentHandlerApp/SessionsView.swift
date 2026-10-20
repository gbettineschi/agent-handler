import SwiftUI
import AgentHandlerCore

struct SessionsView: View {
    let sessions: [SessionSummary]
    var now = Date()
    var dismiss: (SessionSummary) -> Void = { _ in }
    let select: (RequestKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions").font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("Newest first").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8).panelMeasuredHeight(.navigation)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                if let request = session.request {
                                    Button { select(request.id) } label: { SessionRow(session: session, now: now) }
                                        .buttonStyle(SessionOpenStyle()).handlerFocusRing().help("Show question or approval")
                                } else { SessionRow(session: session, now: now) }
                                if session.isFinished {
                                    PanelIconButton(title: "Dismiss finished session: \(session.title)", symbol: "xmark", helpText: "Hide this finished turn. New activity brings it back.") { dismiss(session) }
                                        .padding(.trailing, 10)
                                }
                            }.accessibilityElement(children: .contain)
                            if session.id != sessions.last?.id { Divider().padding(.leading, 44) }
                        }
                    }
                }.padding(.bottom, 8).panelMeasuredHeight(.content)
            }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct SessionRow: View {
    let session: SessionSummary
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if session.status == .running, !reduceMotion {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint) }
            }.frame(width: 18, height: 18).padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                    .multilineTextAlignment(.leading).help(session.title)
                HStack(spacing: 5) {
                    Text(session.sourceLabel).foregroundStyle(.secondary)
                        .help(session.isClaude ? "Claude Desktop · read-only local activity" : "Codex · Desktop connection")
                    Text("·").foregroundStyle(.tertiary)
                    Text(label).foregroundStyle(tint)
                        .help(session.activityDetail == nil ? label : "Latest native activity; updates while the agent runs.")
                    if let remaining = session.remaining(at: now) {
                        Text("·").foregroundStyle(.tertiary)
                        Text(remaining).monospacedDigit().foregroundStyle(.secondary)
                            .help("Included in the menu-bar count for another \(remaining).")
                            .accessibilityLabel("Counted for \(remaining) more")
                    }
                }.font(.system(size: 11))
                if let preview = session.request?.request.title.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                    Text(preview).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if session.request != nil { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 5) }
        }.padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private var label: String {
        if let request = session.request {
            switch request.state {
            case .sending: return "Sending…"
            case .uncertain, .rejected: return "Check source"
            case .unavailable: return "Unavailable"
            default:
                if case .approval = request.request.content { return "Approval" }
                return "Question"
            }
        }
        switch session.status {
        case .running: return session.activityDetail?.label ?? "Running"
        case .needsInput: return "Needs you"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unavailable"
        }
    }
    private var symbol: String {
        if let request = session.request, ![.pending, .sending].contains(request.state) { return "exclamationmark.triangle" }
        switch session.status {
        case .running: return "gearshape"
        case .needsInput: return "exclamationmark.bubble"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .cancelled: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }
    private var tint: Color {
        if let request = session.request, ![.pending, .sending].contains(request.state) { return .orange }
        switch session.status {
        case .running: return .cyan
        case .needsInput: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled, .unknown: return .secondary
        }
    }
}

private struct SessionOpenStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SessionOpenSurface(content: configuration.label, pressed: configuration.isPressed)
    }
}
private struct SessionOpenSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        content.background(Color.primary.opacity(pressed ? 0.10 : hovered ? 0.045 : 0))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovered)
    }
}
