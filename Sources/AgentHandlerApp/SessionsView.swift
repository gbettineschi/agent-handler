import SwiftUI
import AgentHandlerCore

struct SessionsView: View {
    let sessions: [SessionSummary]
    let select: (RequestKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Sessions").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("Latest status").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
                List(sessions) { session in
                    VStack(spacing: 0) {
                    if let request = session.request {
                        Button { select(request.id) } label: { SessionRow(session: session) }
                            .buttonStyle(.plain).help("Show question or approval")
                    } else { SessionRow(session: session) }
                    if session.id != sessions.last?.id { Divider().padding(.leading, 44) }
                    }.listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
                }.listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
}

private struct SessionRow: View {
    let session: SessionSummary
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint).frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                Text(session.request?.request.title.components(separatedBy: .newlines).first ?? (session.isClaude ? "Claude · read-only" : "Desktop · latest turn"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(tint.opacity(0.10), in: Capsule()).fixedSize()
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
        case .running: return "Working"
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
        case .running: return "ellipsis.circle"
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
