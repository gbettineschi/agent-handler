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
    /// Exercise updates in one hosting tree: replacing the window would hide
    /// stale preference regions and viewport-dependent measurement feedback.
    @MainActor private static func verifyAdaptiveTransitions(model: AppModel) async throws {
        await model.loadDemo(.empty)
        model.showSessions = true
        let presentation = PanelPresentation(); presentation.expanded = true
        var measured: CGFloat = 0
        let host = NSHostingView(rootView: HandlerPanelView(model: model, presentation: presentation,
            collapse: {}, contentHeightChanged: { measured = $0 }))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close() }
        func settle() async throws -> CGFloat {
            try await settleHeight(window: window, host: host, width: 420, measured: { measured })
        }
        let three = try await settle()
        let original = model.activities
        model.activities = Array(original.prefix(1)); model.updateSessionPresentation()
        let one = try await settle()
        model.issue = String(repeating: "A multiline warning must stay readable when inserted into a compact panel. ", count: 6)
        let warning = try await settle()
        window.setContentSize(NSSize(width: 420, height: 100))
        let constrainedWarning = try await settle()
        guard abs(constrainedWarning - warning) <= 1 else { throw Failure.dimensions }
        model.issue = nil
        let cleared = try await settle()
        model.showSettings = true
        let settings = try await settle()
        model.showSettings = false
        let returned = try await settle()
        model.activities = []; model.updateSessionPresentation()
        let empty = try await settle()
        model.activities = original; model.updateSessionPresentation()
        let restored = try await settle()
        guard three > one, warning > one, abs(cleared - one) <= 1,
              abs(returned - one) <= 1, abs(restored - three) <= 1, settings > one, empty > 0 else {
            print("Unexpected adaptive sequence: \([three, one, warning, cleared, settings, returned, empty, restored])")
            throw Failure.dimensions
        }
        print("adaptive transitions: \([three, one, warning, cleared, settings, returned, empty, restored])")
    }
    /// Native scrollbars can change text width once when a viewport stops
    /// overflowing. Require two stable layouts, and reject persistent feedback.
    @MainActor private static func settleHeight<V: View>(window: NSWindow, host: NSHostingView<V>,
                                                       width: CGFloat, measured: () -> CGFloat) async throws -> CGFloat {
        var history: [CGFloat] = []
        var stable = 0
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let natural = measured()
            guard natural > 0, natural.isFinite else { throw Failure.dimensions }
            let target = PanelPlacement.menuFrame(visible: CGRect(x: 0, y: 0, width: 1200, height: 1000),
                                                  anchor: nil, contentHeight: natural).height
            let alreadyFits = abs(host.bounds.height - target) <= 1
            if alreadyFits, let previous = history.last, abs(previous - natural) <= 1 { stable += 1 }
            else { stable = 0 }
            history.append(natural)
            if stable >= 2 { return natural }
            window.setContentSize(NSSize(width: width, height: target))
        }
        print("Height did not converge in six layouts: \(history)")
        throw Failure.dimensions
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
            ("sessions-narrow", .empty, 340, 400, true, false, false),
            ("quota-narrow", .questions, 340, 400, true, false, false),
            ("quota-unavailable", .empty, 420, 400, true, false, false),
            ("sessions-thinking", .empty, 420, 400, true, false, false),
            ("finished-expired", .empty, 420, 400, true, false, false),
            ("sessions-long-titles", .empty, 420, 400, true, false, false),
            ("sessions-recent", .empty, 420, 400, true, false, false),
            ("sessions-undo", .empty, 420, 400, true, false, false),
            ("sessions-many", .empty, 420, 400, true, false, false),
            ("empty", .empty, 420, 260, true, false, false),
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
            if name == "finished-expired" {
                model.updateSessionPresentation(now: Date().addingTimeInterval(301))
                precondition(model.sessions.count == 1 && model.sessions.allSatisfy { !$0.isFinished })
            }
            if name == "sessions-thinking" {
                var activity = ActivityStore()
                for entry in model.activities {
                    let epoch = activity.begin(scope: entry.id)
                    activity.observe(.init(scope: entry.id, epoch: epoch, revision: 1, turnID: entry.turnID,
                        phase: .running, attention: .clear, detail: .thinking))
                }
                model.activities = activity.views; model.updateSessionPresentation()
                precondition(model.sessions.allSatisfy { $0.activityDetail == .thinking })
            }
            if name == "sessions-long-titles" {
                for activity in model.activities {
                    model.titles[activity.id.conversation] = "A long conversation title — review the implementation, check the remaining details and prepare the next release"
                }
            }
            if name == "sessions-recent" {
                let completed = model.activities
                var running = ActivityStore()
                for activity in completed {
                    let epoch = running.begin(scope: activity.id)
                    running.observe(.init(scope: activity.id, epoch: epoch, revision: 1, turnID: activity.turnID, phase: .running, attention: .clear))
                }
                model.activities = running.views; model.updateSessionPresentation()
                model.activities = completed; model.updateSessionPresentation()
                precondition(model.sessions.contains { $0.recentUntil != nil })
            }
            if name == "sessions-undo", let finished = model.sessions.first(where: \.isFinished) {
                model.dismissSession(finished)
                precondition(model.dismissal != nil && model.sessions.count == 2)
            }
            if name == "sessions-many" {
                var activity = ActivityStore()
                for index in 1...16 {
                    let scope = RequestScope(installation: "demo", conversation: "visual-\(index)")
                    let epoch = activity.begin(scope: scope)
                    activity.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: index < 5 ? .running : .completed, attention: .clear))
                    model.titles[scope.conversation] = "Example session \(index)"
                }
                model.activities = activity.views; model.updateSessionPresentation()
                precondition(model.sessions.count == 16)
            }
            if name == "empty" {
                model.activities = []; model.requests = []; model.updateSessionPresentation()
                precondition(model.sessions.isEmpty)
            }
            if name == "quota-unavailable" { model.codexUsage = nil }
            if name == "quota-narrow", let finished = model.sessions.first(where: \.isFinished) {
                model.dismissSession(finished)
                precondition(!model.hiddenSessions.isEmpty && !model.requests.isEmpty)
            }
            let presentation = PanelPresentation()
            presentation.expanded = expanded
            var measuredHeight: CGFloat = 0
            let root = HandlerPanelView(model: model, presentation: presentation, collapse: {},
                                        contentHeightChanged: { measuredHeight = $0 })
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            let bounds = NSRect(x: 0, y: 0, width: width, height: height)
            let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: contrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.setFrameSize(bounds.size)
            _ = try await settleHeight(window: window, host: host, width: width, measured: { measuredHeight })
            let adaptiveHeight = window.contentView!.bounds.height
            if name == "sessions-many" { precondition(adaptiveHeight == 640) }
            if name == "empty" { precondition(adaptiveHeight < 260) }
            guard abs(host.bounds.width - width) < 0.5, abs(host.bounds.height - adaptiveHeight) < 0.5 else {
                print("Unexpected size for \(name): \(host.bounds.size), expected \(width)×\(adaptiveHeight)")
                throw Failure.dimensions
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure.render }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let bytes = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
            try bytes.write(to: output.appendingPathComponent(name + ".png"))
            window.close()
            print("\(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
        }
        try await verifyAdaptiveTransitions(model: model)
        await model.loadDemo(.empty)
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        model.updateSessionPresentation()
        let initialOrder = model.sessions.map(\.id)
        model.recentConversationIDs.reverse(); model.activities.reverse()
        model.updateSessionPresentation()
        guard model.sessions.map(\.id) == initialOrder, let target = initialOrder.last else { throw Failure.dimensions }
        var input = ActivityStore()
        for activity in model.activities {
            let epoch = input.begin(scope: activity.id)
            input.observe(.init(scope: activity.id, epoch: epoch, revision: 1, turnID: activity.turnID,
                phase: activity.id == target ? .running : activity.phase, attention: .clear,
                humanInputID: activity.id == target ? "native-human-input" : nil))
        }
        model.activities = input.views; model.updateSessionPresentation()
        guard model.sessions.first?.id == target else { throw Failure.dimensions }
        print("session ordering: metadata refresh stays stable; native human input promotes its row")
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
