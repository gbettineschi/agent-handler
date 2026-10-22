import SwiftUI
import AgentHandlerCore

struct SessionsView: View {
    let sessions: [SessionSummary]
    var dismiss: (SessionSummary) -> Void = { _ in }
    let select: (RequestKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sessions").font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
            }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8).panelMeasuredHeight(.navigation)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                if let request = session.request {
                                    Button { select(request.id) } label: { SessionRow(session: session) }
                                        .buttonStyle(SessionOpenStyle()).handlerFocusRing().help("Show question or approval")
                                } else { SessionRow(session: session) }
                                if session.isFinished {
                                    PanelIconButton(title: "Dismiss finished session: \(session.title)", symbol: "xmark", helpText: "Hide this finished turn. New activity brings it back.", subtle: true) { dismiss(session) }
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
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if session.status == .running {
                    RunningAgentIndicator()
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
                }.font(.system(size: 11))
                if !sourceOnly, let preview = session.request?.request.title.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                    Text(preview).font(.system(size: 12)).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                if session.needsSourceApproval {
                    Text(sourceOnly ? "This request needs the Codex app." : "Another request needs the Codex app.").font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if session.request != nil { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 5) }
        }.padding(.horizontal, 16).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private var sourceOnly: Bool {
        session.needsSourceApproval && (session.request.map { ![.pending, .sending].contains($0.state) } ?? true)
    }
    private var label: String {
        if sourceOnly { return "Review in Codex" }
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
        case .unknown: return session.hasUnresolvedSourceInput ? "Check \(session.sourceLabel)" : "Unavailable"
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
        case .unknown: return session.hasUnresolvedSourceInput ? "exclamationmark.bubble" : "questionmark.circle"
        }
    }
    private var tint: Color {
        if let request = session.request, ![.pending, .sending].contains(request.state) { return .orange }
        switch session.status {
        case .running: return .blue
        case .needsInput: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .unknown: return session.hasUnresolvedSourceInput ? .orange : .secondary
        }
    }
}

/// The same original agent artwork as the menu bar, in blue with a gentle bob/blink.
/// Four frames at a low cadence; Reduce Motion keeps a still agent instead.
private struct RunningAgentIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let frames = (0..<4).map { AgentStatusIcon.image(mode: .working, frame: $0) }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3, paused: reduceMotion)) { context in
            let frame = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 4
            Image(nsImage: Self.frames[frame]).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(.blue)
        }.frame(width: 22, height: 18)
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
