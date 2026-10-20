import AppKit
import SwiftUI
import AgentHandlerCore
@testable import AgentHandlerApp

/// Production views in unshown fixture windows. No input injection,
/// agent connection, source-app interaction or settings changes.
@main struct RenderUI {
    @MainActor static func main() async {
        do { try await render() }
        catch {
            FileHandle.standardError.write(Data("UI rendering failed: \(error)\n".utf8))
            exit(1)
        }
    }
    @MainActor private static func render() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/ui-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = try AppModel(demo: true)
        let cases: [(String, DemoScenario, CGFloat, CGFloat, Bool, Bool, Bool)] = [
            ("question", .questions, 420, 400, true, false, false),
            ("approval", .approval, 420, 480, true, false, false),
            ("long-content", .longContent, 420, 400, true, false, false),
            ("long-narrow", .longContent, 340, 400, true, false, false),
            ("unavailable", .unavailable, 420, 400, true, false, false),
            ("uncertain", .uncertain, 420, 480, true, false, false),
            ("sessions", .empty, 420, 400, true, false, false),
            ("settings", .questions, 420, 480, true, true, false),
            ("appearance-high-contrast", .questions, 420, 400, true, false, true)
        ]
        for (name, scenario, width, height, expanded, settings, contrast) in cases {
            await model.loadDemo(scenario)
            model.requests = await model.core.snapshot().filter(\.needsAttention)
            model.updateSessionPresentation()
            model.showSessions = scenario == .empty
            model.showSettings = settings
            if scenario == .unavailable { precondition(model.requests.allSatisfy { $0.state == .unavailable }) }
            if scenario == .uncertain { precondition(model.requests.count == 1 && model.requests[0].state == .uncertain) }
            if scenario == .empty { precondition(model.requests.isEmpty && model.sessions.count == 3) }
            let presentation = PanelPresentation()
            presentation.expanded = expanded
            let root = HandlerPanelView(model: model, presentation: presentation, collapse: {})
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let bounds = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: contrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.setFrameSize(bounds.size)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            host.layoutSubtreeIfNeeded()
            guard abs(host.bounds.width - width) < 0.5, abs(host.bounds.height - height) < 0.5 else {
                print("Unexpected size for \(name): \(host.bounds.size), expected \(width)×\(height)")
                throw Failure.dimensions
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure.render }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let bytes = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
            try bytes.write(to: output.appendingPathComponent(name + ".png"))
            window.close()
            print("\(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
        let gallery = NSHostingView(rootView: IconGallery())
        gallery.sizingOptions = []
        gallery.appearance = NSAppearance(named: .darkAqua)
        gallery.frame = NSRect(x: 0, y: 0, width: 420, height: 260)
        gallery.layoutSubtreeIfNeeded()
        if let bitmap = gallery.bitmapImageRepForCachingDisplay(in: gallery.bounds) {
            gallery.cacheDisplay(in: gallery.bounds, to: bitmap)
            if let bytes = bitmap.representation(using: .png, properties: [:]) {
                try bytes.write(to: output.appendingPathComponent("status-glyphs.png"))
            } else { throw Failure.render }
        } else { throw Failure.render }
        for (name, mode) in [("idle", MenuBarState.Mode.idle), ("working", .working), ("attention", .attention), ("unavailable", .unavailable), ("failed", .failed), ("recent", .recent), ("paused", .paused)] {
            for frame in 0..<(mode == .working ? 4 : 1) {
                let image = AgentStatusIcon.image(mode: mode, frame: frame)
                guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
                try png.write(to: output.appendingPathComponent("icon-\(name)-\(frame).png"))
            }
        }
    }
    enum Failure: Error { case render, dimensions }
}

private struct IconGallery: View {
    private let modes: [(String, MenuBarState.Mode)] = [("Idle", .idle), ("Working · animation frames", .working), ("Needs input", .attention), ("Unavailable", .unavailable), ("Failed", .failed), ("Recently finished", .recent), ("Paused", .paused)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(modes, id: \.0) { name, mode in
                HStack {
                    Text(name).font(.system(size: 12)).frame(width: 205, alignment: .leading)
                    ForEach(0..<(mode == .working ? 4 : 1), id: \.self) { frame in
                        Image(nsImage: AgentStatusIcon.image(mode: mode, frame: frame)).renderingMode(.template)
                            .frame(width: 22, height: 18)
                    }
                    if mode != .working { Text(mode == .idle || mode == .paused ? "0" : "1").font(.system(size: 11).monospacedDigit()) }
                }.frame(height: 22)
            }
        }.padding(20).frame(width: 420, height: 260, alignment: .topLeading)
            .foregroundStyle(.white).background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
    }
}
