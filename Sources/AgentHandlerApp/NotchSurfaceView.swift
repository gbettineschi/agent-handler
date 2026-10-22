import AppKit
import SwiftUI

/// One hosting tree in both presentations: changing placement never replaces
/// the request view or the drafts it owns.
struct CompanionSurfaceView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: PanelPresentation
    let open: () -> Void
    let settings: () -> Void
    let collapse: () -> Void
    var contentHeightChanged: (CGFloat) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if presentation.style == .notch {
                NotchStatusStrip(state: model.menuBarState, cameraWidth: presentation.cameraWidth,
                    height: presentation.stripHeight, expanded: presentation.expanded, activate: open)
                    .contextMenu {
                        Button("Open Agent Handler", action: open)
                        Button("Settings…", action: settings)
                        Divider()
                        Button("Quit Agent Handler") { NSApp.terminate(nil) }
                    }
            }
            HandlerPanelView(model: model, presentation: presentation, collapse: collapse,
                contentHeightChanged: contentHeightChanged)
                .frame(height: presentation.style == .notch && !presentation.expanded ? 0 : nil)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(presentation.style == .notch ? Color.black : Color.clear)
        .clipShape(CompanionOutline(style: presentation.style, expanded: presentation.expanded))
        .environment(\.colorScheme, .dark)
    }
}

struct NotchStatusStrip: View {
    let state: MenuBarState
    let cameraWidth: CGFloat
    let height: CGFloat
    let expanded: Bool
    let activate: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 0) {
                TimelineView(.animation(minimumInterval: 0.25, paused: expanded || !state.shouldAnimate(reduceMotion: reduceMotion))) { context in
                    let frame = !expanded && state.shouldAnimate(reduceMotion: reduceMotion)
                        ? Int(context.date.timeIntervalSinceReferenceDate * 4) % 4 : 0
                    Image(nsImage: AgentStatusIcon.image(mode: state.mode, frame: frame))
                        .renderingMode(.template).foregroundStyle(tint)
                        .frame(width: 22, height: 18)
                }.frame(width: 48).opacity(expanded ? 0 : 1)
                Color.clear.frame(width: cameraWidth, height: 1).accessibilityHidden(true)
                Text("\(state.working)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(state.working > 0 ? .white : .white.opacity(0.5))
                    .frame(width: 48)
                    .opacity(expanded ? 0 : 1)
            }.frame(maxWidth: .infinity).frame(height: height)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            // Only the compact content fades. AppKit remains the sole owner
            // of window size; the camera clearance and click surface stay put.
            .animation(reduceMotion ? nil : .easeOut(duration: expanded ? 0.10 : 0.16), value: expanded)
            .accessibilityLabel("Agent Handler. \(state.working) running. \(state.needsInput) need input.")
            .help(expanded ? "Click to keep open." : "\(state.working) running · \(state.needsInput) need input. Hover to expand; click to keep open.")
    }
    private var tint: Color {
        switch state.mode {
        case .working: .blue
        case .attention, .unavailable: .orange
        case .failed: .red
        case .recent: .green
        case .idle, .paused: .white.opacity(0.55)
        }
    }
}

/// Attached shoulders, square against the screen edge, with a continuous black
/// body below the camera. Unlike a floating capsule, there is no top gap.
struct CompanionOutline: Shape {
    let style: CompanionStyle
    let expanded: Bool
    func path(in rect: CGRect) -> Path {
        guard style == .notch else {
            return Path(roundedRect: rect, cornerRadius: 12)
        }
        let shoulder: CGFloat = expanded ? 12 : 6
        let radius: CGFloat = min(expanded ? 22 : 9, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
            control: CGPoint(x: rect.width - shoulder, y: 0))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder - radius, y: rect.height),
            control: CGPoint(x: rect.width - shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: shoulder, y: rect.height - radius),
            control: CGPoint(x: shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addQuadCurve(to: .zero, control: CGPoint(x: shoulder, y: 0))
        path.closeSubpath()
        return path
    }
}
