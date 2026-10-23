import AppKit
import SwiftUI
@testable import AgentHandlerCore
@testable import AgentHandlerApp

/// Production views in fixture windows, plus a native panel lifetime check. No input injection,
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
        var interrupted = ActivityStore()
        for entry in original {
            let epoch = interrupted.begin(scope: entry.id)
            interrupted.observe(.init(scope: entry.id, epoch: epoch, revision: 1, turnID: entry.turnID,
                phase: entry.phase, attention: .clear))
            if entry.phase != .running { interrupted.invalidate(scope: entry.id, epoch: epoch) }
        }
        model.activities = interrupted.views; model.updateSessionPresentation()
        let disconnected = try await settle()
        guard model.activities.count == 3, model.sessions.count == 1, disconnected < three else { throw Failure.dimensions }
        model.activities = original; model.updateSessionPresentation()
        let reconnected = try await settle()
        guard abs(reconnected - three) <= 1 else { throw Failure.dimensions }
        print("session availability: stale rows hide and panel shrinks; fresh activity returns without a finish event")
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
                                                       width: CGFloat, extraHeight: CGFloat = 0,
                                                       sizeChanged: (CGSize) -> Void = { _ in }, measured: () -> CGFloat) async throws -> CGFloat {
        var history: [CGFloat] = []
        var stable = 0
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let natural = measured()
            guard natural > 0, natural.isFinite else { throw Failure.dimensions }
            let target = PanelPlacement.menuFrame(visible: CGRect(x: 0, y: 0, width: 1200, height: 1000),
                                                  anchor: nil, contentHeight: natural).height + extraHeight
            sizeChanged(CGSize(width: width, height: target))
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
    /// A native panel owned by this fixture process, with the real controller
    /// and synthetic transport. No source app or personal request is touched.
    @MainActor private static func verifyAutomaticClosing(model: AppModel) async throws {
        model.companionStyle = .menuBar
        await model.loadDemo(.approval)
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        guard let request = model.requests.first?.request else { throw Failure.render }
        let panel = MenuBarPanel(model: model)
        defer { panel.shutdown() }
        var visibility: [Bool] = []
        panel.visibilityChanged = { visibility.append($0) }
        model.attentionChanged = { panel.refresh() }
        defer { model.attentionChanged = nil }
        panel.showAutomatically(for: .request(request.key))
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "Agent Handler" }),
              window.isVisible else { throw Failure.dimensions }
        defer { window.performClose(nil) }
        try await model.core.respond(key: request.key, fingerprint: request.fingerprint, answer: .decision("accept"), using: DemoTransport(outcome: .uncertain))
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        model.updateSessionPresentation()
        guard window.isVisible, model.requests.first?.state == .uncertain else { throw Failure.dimensions }
        let epoch = await model.core.begin(scope: request.key.scope)
        await model.core.observe(.init(scope: request.key.scope, epoch: epoch, revision: 1, requests: []))
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        model.updateSessionPresentation()
        guard !window.isVisible, visibility == [true, false] else { throw Failure.dimensions }
        panel.show()
        model.updateSessionPresentation()
        guard window.isVisible else { throw Failure.dimensions }
        window.performClose(nil)
        await model.loadDemo(.approval)
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        guard let next = model.requests.first?.request else { throw Failure.render }
        panel.showAutomatically(for: .request(next.key))
        model.showSettings = true; panel.refresh()
        let nextEpoch = await model.core.begin(scope: next.key.scope)
        await model.core.observe(.init(scope: next.key.scope, epoch: nextEpoch, revision: 1, requests: []))
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        model.updateSessionPresentation()
        guard window.isVisible else { throw Failure.dimensions }
        print("automatic panel lifetime: uncertain stays visible; authoritative withdrawal hides; manual and Settings stay visible")
        window.performClose(nil)
        model.showSettings = false; model.activities = []; model.requests = []
        model.observedCodexConversations = ["source-only"]; model.sourceApprovalConversations = ["source-only"]
        model.updateSessionPresentation()
        let scope = model.sessions.first!.id
        panel.showAutomatically(for: .sessions)
        guard window.isVisible, model.sessions.first?.status == .needsInput else { throw Failure.dimensions }
        model.sourceApprovalConversations = []; model.updateSessionPresentation()
        guard window.isVisible, model.sessions.first?.status == .unknown else { throw Failure.dimensions }
        var recovered = ActivityStore()
        let recovery = recovered.begin(scope: scope)
        recovered.observe(.init(scope: scope, epoch: recovery, revision: 1, turnID: "recovered-turn", phase: .running, attention: .clear))
        model.activities = recovered.views; model.updateSessionPresentation()
        guard !window.isVisible else { throw Failure.dimensions }
        print("source-only panel lifetime: native wait stays visible; unknown data retains its row; positive recovery hides")
    }
    /// Same production NSPanel and pointer handler. The fake geometry/position
    /// belong only to this process; no cursor movement or source-app input.
    @MainActor private static func verifyNotchInteraction(model: AppModel) async throws {
        await model.loadDemo(.questions)
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        model.companionStyle = .notch
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        let safe: CGFloat = 38
        guard let geometry = NotchGeometry.resolve(screen: screen, visible: screen.insetBy(dx: 0, dy: 40), safeTop: safe,
            left: CGRect(x: screen.minX, y: screen.maxY - safe, width: screen.width / 2 - 96, height: safe),
            right: CGRect(x: screen.midX + 96, y: screen.maxY - safe, width: screen.width / 2 - 96, height: safe)) else { throw Failure.dimensions }
        var available = true
        var pointer = CGPoint(x: screen.minX + 10, y: screen.minY + 10)
        let panel = MenuBarPanel(model: model, notchGeometry: { available ? geometry : nil }, pointerLocation: { pointer })
        model.attentionChanged = { panel.refresh() }
        defer { model.attentionChanged = nil; panel.shutdown(); model.companionStyle = .menuBar }
        panel.refresh()
        guard let window = NSApplication.shared.windows.first(where: { $0.title == "Agent Handler" && $0.isVisible }) else {
            print("Notch fixture has no visible panel"); throw Failure.dimensions
        }
        func check(_ condition: Bool, _ step: String) throws {
            guard condition else {
                print("Notch fixture failed at \(step): expanded=\(panel.isExpanded) visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(window.frame)")
                throw Failure.dimensions
            }
        }
        try check(panel.effectiveStyle == .notch && !panel.isExpanded && window.frame == geometry.collapsedFrame, "initial collapsed placement")
        // Dispatch only within this fixture process. A missed view-entry event
        // must not prevent geometric hover, including over the camera region.
        func move(to point: CGPoint) throws {
            pointer = point
            guard let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else { throw Failure.render }
            NSApp.sendEvent(event)
        }
        for x in [geometry.collapsedFrame.minX + 1, geometry.notch.midX, geometry.collapsedFrame.maxX - 1] {
            // Repeated movement must not keep restarting the opening dwell.
            for offset in 0..<8 {
                try move(to: CGPoint(x: x, y: geometry.collapsedFrame.maxY - 1 - CGFloat(offset % 2)))
                try await Task.sleep(for: .milliseconds(35))
            }
            try check(panel.isExpanded && !window.isKeyWindow, "mouse movement recovers missed entry at x=\(x)")
            try move(to: CGPoint(x: screen.minX + 10, y: screen.minY + 10))
            try await Task.sleep(for: .milliseconds(600))
            try check(!panel.isExpanded, "mouse movement exit folds")
        }
        pointer = CGPoint(x: geometry.collapsedFrame.minX + 24, y: geometry.collapsedFrame.midY)
        panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(panel.isExpanded && window.isVisible && !window.isKeyWindow, "hover without focus")
        pointer = CGPoint(x: screen.minX + 10, y: screen.minY + 10)
        panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(600))
        try check(!panel.isExpanded && window.isVisible && abs(window.frame.height - geometry.stripHeight) < 1, "leave folds")

        pointer = CGPoint(x: geometry.collapsedFrame.minX + 24, y: geometry.collapsedFrame.midY)
        panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(panel.isExpanded, "second hover")
        panel.show()
        pointer = CGPoint(x: screen.minX + 10, y: screen.minY + 10); panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(panel.isExpanded, "explicit pin survives leave")
        pointer = CGPoint(x: geometry.notch.midX, y: geometry.collapsedFrame.minY - 20)
        panel.pointerChanged() // Cache inside the expanded body, outside the compact trigger.
        window.performClose(nil)
        try move(to: CGPoint(x: geometry.collapsedFrame.minX + 24, y: geometry.collapsedFrame.midY))
        try await Task.sleep(for: .milliseconds(450))
        try check(panel.isExpanded, "first compact movement after body collapse starts dwell")
        panel.show()
        pointer = CGPoint(x: geometry.notch.midX, y: geometry.collapsedFrame.minY - 2)
        window.performClose(nil); panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(!panel.isExpanded, "shrinking body is not a new hover trigger")
        panel.show()
        try await Task.sleep(for: .milliseconds(250))
        pointer = CGPoint(x: geometry.collapsedFrame.minX + 24, y: geometry.collapsedFrame.midY)
        window.performClose(nil)
        panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(!panel.isExpanded && window.isVisible, "explicit collapse suppresses reopen")
        pointer = CGPoint(x: screen.minX + 10, y: screen.minY + 10)
        panel.pointerChanged()
        guard let request = model.requests.first?.request else { throw Failure.render }
        panel.showAutomatically(for: .request(request.key))
        panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(panel.isExpanded && !window.isKeyWindow, "automatic opening")
        try await model.core.respond(key: request.key, fingerprint: request.fingerprint, answer: .text("Synthetic notch check"), using: DemoTransport(outcome: .uncertain))
        model.requests = await model.core.snapshot().filter(\.needsAttention); model.updateSessionPresentation()
        try check(panel.isExpanded && model.requests.contains(where: { $0.state == .uncertain }), "uncertain retention")
        let epoch = await model.core.begin(scope: request.key.scope)
        await model.core.observe(.init(scope: request.key.scope, epoch: epoch, revision: 1, requests: []))
        model.requests = await model.core.snapshot().filter(\.needsAttention); model.updateSessionPresentation()
        try check(!panel.isExpanded && window.isVisible, "resolved folds")

        panel.showSettings(); pointer = CGPoint(x: screen.minX + 10, y: screen.minY + 10); panel.pointerChanged()
        try await Task.sleep(for: .milliseconds(450))
        try check(panel.isExpanded && model.showSettings, "Settings ownership")
        available = false; panel.refresh()
        try check(panel.effectiveStyle == .menuBar && model.companionStyle == .notch && panel.isExpanded && model.showSettings, "display fallback")
        available = true; panel.refresh()
        try check(panel.effectiveStyle == .notch && panel.isExpanded && model.showSettings, "display recovery")
        model.companionStyle = .menuBar; panel.refresh()
        try check(panel.effectiveStyle == .menuBar && panel.isExpanded, "menu-bar return")
        print("notch lifecycle: mouse-movement dispatch recovers missed entry at left/camera/right without focus or dwell starvation; leave folds and re-entry opens; explicit collapse suppresses reopen; uncertain/automatic waits stay; resolution folds; Settings and display fallback preserve route")
    }
    /// Observe the real scroll viewport during expansion, not just its settled
    /// size. A short list must fit throughout the reveal, without a scroller.
    @MainActor private static func verifyNotchExpansionLayout(model: AppModel) async throws {
        await model.loadDemo(.empty)
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        model.showSettings = false; model.showSessions = true; model.companionStyle = .notch
        model.updateSessionPresentation()
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        guard let geometry = NotchGeometry.resolve(screen: screen, visible: screen.insetBy(dx: 0, dy: 40), safeTop: 38,
            left: CGRect(x: 0, y: 944, width: 660, height: 38),
            right: CGRect(x: 852, y: 944, width: 660, height: 38)) else { throw Failure.dimensions }
        var available = true
        let panel = MenuBarPanel(model: model, notchGeometry: { available ? geometry : nil }, pointerLocation: { .zero })
        model.attentionChanged = { panel.refresh() }
        defer { model.attentionChanged = nil; panel.shutdown(); model.companionStyle = .menuBar }
        panel.refresh()
        guard let window = NSApp.windows.first(where: { $0.title == "Agent Handler" && $0.isVisible }),
              let host = window.contentView else { throw Failure.render }
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        var samples: [String] = []
        var viewportWidths: [CGFloat] = []
        var overflow = false
        panel.show()
        for index in 0..<40 {
            host.layoutSubtreeIfNeeded()
            for scroll in scrollViews(host) {
                guard let document = scroll.documentView, document.bounds.height > 0 else { continue }
                let viewport = scroll.contentView.bounds.size
                viewportWidths.append(viewport.width)
                if window.frame.height > geometry.stripHeight + 4 && document.bounds.height > viewport.height + 1 {
                    overflow = true
                }
                if index < 14 || index == 39 {
                    samples.append("\(index): window \(Int(window.frame.width))×\(Int(window.frame.height)), viewport \(Int(viewport.width))×\(Int(viewport.height)), document \(Int(document.bounds.width))×\(Int(document.bounds.height))")
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        print("notch expansion samples: \(samples.joined(separator: "; "))")
        guard !samples.isEmpty, !overflow, let minWidth = viewportWidths.min(), let maxWidth = viewportWidths.max(),
              maxWidth - minWidth < 1, window.frame.width == 520,
              window.frame.height > geometry.stripHeight + 100 else {
            print("Short sessions overflow while the notch expands")
            throw Failure.dimensions
        }
        print("notch expansion: short sessions fit during every sampled frame")

        let shortActivities = model.activities
        var many = ActivityStore()
        for index in 0..<20 {
            let scope = RequestScope(installation: "demo", conversation: "animation-list-\(index)")
            let epoch = many.begin(scope: scope)
            many.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "synthetic-turn", phase: .running, attention: .clear))
            model.titles[scope.conversation] = "Synthetic session \(index + 1)"
        }
        model.activities = many.views; model.updateSessionPresentation()
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        guard let longScroll = scrollViews(host).first(where: { scroll in
            guard let document = scroll.documentView else { return false }
            return scroll.contentView.bounds.height > 100 && document.bounds.height > scroll.contentView.bounds.height + 100
        }) else { throw Failure.dimensions }
        longScroll.contentView.scroll(to: CGPoint(x: 0, y: 100))
        longScroll.reflectScrolledClipView(longScroll.contentView)
        guard longScroll.contentView.bounds.minY > 0 else { throw Failure.dimensions }
        model.activities = shortActivities; model.updateSessionPresentation()
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        guard scrollViews(host).allSatisfy({ ($0.documentView?.bounds.height ?? 0) <= $0.contentView.bounds.height + 1 && $0.contentView.bounds.minY <= 1 }) else { throw Failure.dimensions }
        print("notch content updates: long lists retain a scroll viewport; short lists return to a fitting viewport")
        window.performClose(nil); panel.show()
        try await Task.sleep(for: .milliseconds(450))
        guard panel.isExpanded, window.frame.width == 520, window.frame.height > geometry.stripHeight + 100 else {
            print("Immediate close/reopen did not reveal its unchanged content: \(window.frame)")
            throw Failure.dimensions
        }
        print("notch rapid reopen: unchanged natural height still starts the reveal")
        available = false; panel.refresh()
        available = true; panel.refresh()
        try await Task.sleep(for: .milliseconds(450))
        guard panel.effectiveStyle == .notch, panel.isExpanded, window.frame.width == 520,
              window.frame.height > geometry.stripHeight + 100 else { throw Failure.dimensions }
        print("notch rapid display recovery: unchanged content is measured and revealed")
        window.performClose(nil)
        panel.show(); window.performClose(nil)
        try await Task.sleep(for: .milliseconds(450))
        guard !panel.isExpanded, window.frame == geometry.collapsedFrame else { throw Failure.dimensions }
        print("notch cancelled opening: late layout cannot reopen a dismissed panel")
    }
    @MainActor private static func renderNotchVariants(model: AppModel, output: URL) async throws {
        for (name, scenario, expanded, settings) in [
            ("notch-collapsed", DemoScenario.empty, false, false),
            ("notch-sessions", .empty, true, false),
            ("notch-question", .questions, true, false),
            ("notch-approval", .approval, true, false),
            ("notch-settings", .empty, true, true),
            ("notch-long", .longContent, true, false)
        ] {
            await model.loadDemo(scenario)
            model.requests = await model.core.snapshot().filter(\.needsAttention)
            model.showSessions = scenario == .empty; model.showSettings = settings
            model.companionStyle = .notch; model.notchAvailable = true
            model.updateSessionPresentation()
            let presentation = PanelPresentation()
            presentation.style = .notch; presentation.expanded = expanded
            presentation.cameraWidth = 203; presentation.stripHeight = 39
            var measured: CGFloat = 0
            let host = NSHostingView(rootView: CompanionSurfaceView(model: model, presentation: presentation,
                open: {}, settings: {}, collapse: {}, contentHeightChanged: { measured = $0 }))
            host.sizingOptions = []
            let width: CGFloat = expanded ? 520 : 299
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: expanded ? 400 : 39),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.isReleasedWhenClosed = false; window.contentView = host
            if expanded {
                _ = try await settleHeight(window: window, host: host, width: width, extraHeight: 39,
                    sizeChanged: { size in
                        let viewport = CGSize(width: size.width, height: size.height - 39)
                        if presentation.contentViewport != viewport { presentation.contentViewport = viewport }
                    }, measured: { measured })
            }
            else { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(150)) }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure.render }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsHigh) / host.bounds.height
            let shoulder: CGFloat = expanded ? 12 : 6
            func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
                bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? .nan
            }
            // The mask belongs to the real window viewport, not the wider
            // fixed content canvas. A side pixel is filled but its curved
            // bottom corner must be transparent in both presentations.
            guard alpha(shoulder + 1, host.bounds.height / 2) > 0.95,
                  alpha(shoulder + 1, host.bounds.height - 2) < 0.05,
                  alpha(host.bounds.width - shoulder - 2, host.bounds.height - 2) < 0.05,
                  alpha(host.bounds.width / 2, host.bounds.height - 2) > 0.95 else {
                print("Notch corners are clipped square: \(name)")
                throw Failure.render
            }
            // The compact indicators must leave the camera band when content
            // is expanded. Sample the actual rendered view, not its properties.
            if expanded {
                for y in Int(6 * scale)..<Int(32 * scale) {
                    for x in Int(24 * scale)..<(bitmap.pixelsWide - Int(24 * scale)) {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                              max(color.redComponent, color.greenComponent, color.blueComponent) < 0.04 else {
                            print("Expanded notch still has compact content in its camera band: \(name)")
                            throw Failure.render
                        }
                    }
                }
            }
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
            try data.write(to: output.appendingPathComponent(name + ".png"))
            print("\(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
            window.close()
        }
        model.companionStyle = .menuBar; model.showSettings = false
    }
    @MainActor private static func render() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/ui-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = try AppModel(demo: true)
        model.companionStyle = .menuBar
        if CommandLine.arguments.contains("--notch-surface-only") {
            try await renderNotchVariants(model: model, output: output)
            return
        }
        if CommandLine.arguments.contains("--notch-animation-only") {
            try await verifyNotchExpansionLayout(model: model)
            return
        }
        if CommandLine.arguments.contains("--notch-interaction-only") {
            try await verifyNotchInteraction(model: model)
            return
        }
        let cases: [(String, DemoScenario, CGFloat, CGFloat, Bool, Bool, Bool)] = [
            ("question", .questions, 420, 400, true, false, false),
            ("approval", .approval, 420, 480, true, false, false),
            ("approval-narrow", .approval, 340, 480, true, false, false),
            ("approval-long", .approval, 340, 480, true, false, false),
            ("approval-browser", .approval, 420, 400, true, false, false),
            ("long-content", .longContent, 420, 400, true, false, false),
            ("long-narrow", .longContent, 340, 400, true, false, false),
            ("unavailable", .unavailable, 420, 400, true, false, false),
            ("uncertain", .uncertain, 420, 480, true, false, false),
            ("sessions", .empty, 420, 400, true, false, false),
            ("sessions-narrow", .empty, 340, 400, true, false, false),
            ("sessions-disconnected", .empty, 420, 400, true, false, false),
            ("permission-wait-disconnected", .empty, 420, 400, true, false, false),
            ("source-only-approval", .empty, 420, 400, true, false, false),
            ("source-state-unavailable", .empty, 340, 400, true, false, false),
            ("source-only-retained", .empty, 340, 400, true, false, false),
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
            model.claudeActivities = []
            model.requests = await model.core.snapshot().filter(\.needsAttention)
            if ["approval-long", "approval-browser"].contains(name), let old = model.requests.first?.request {
                let details: ApprovalDetails
                if name == "approval-browser" {
                    details = .init(subject: .access(message: "Allow Browser use to access this website?", targetLabel: "Website", target: "https://example.com", notices: ["Requests direct browser control."], technicalDetails: "Native browser permission details"), persistentActions: ["always": .savedPermission])
                } else {
                    details = .init(subject: .command(command: "example-tool" + String(repeating: " --example='a value with spaces'", count: 20), directory: "/Users/example/Projects/" + String(repeating: "a-long-folder/", count: 10), reason: "This is a synthetic approval with long command and folder text. No command will run."), persistentActions: ["rule": .commandRule(prefix: ["example-tool", "--example=a value with spaces"])])
                }
                let choices: [ResponseOption] = name == "approval-browser"
                    ? [.init(id: "once", label: "Allow once"), .init(id: "always", label: "Always allow"), .init(id: "deny", label: "Deny")]
                    : [.init(id: "accept", label: "Allow once"), .init(id: "rule", label: "Original native rule label"), .init(id: "cancel", label: "Cancel turn")]
                let request = AttentionRequest(key: old.key, owner: old.owner, title: "Synthetic native approval", content: .approval(choices: choices), approvalDetails: details)
                let epoch = await model.core.begin(scope: old.key.scope)
                await model.core.observe(.init(scope: old.key.scope, epoch: epoch, revision: 1, requests: [request]))
                model.requests = await model.core.snapshot().filter(\.needsAttention)
            }
            model.updateSessionPresentation()
            model.showSessions = scenario == .empty
            model.showSettings = settings
            if scenario == .unavailable { precondition(model.requests.allSatisfy { $0.state == .unavailable }) }
            if scenario == .uncertain { precondition(model.requests.count == 1 && model.requests[0].state == .uncertain) }
            if scenario == .empty { precondition(model.requests.isEmpty && model.sessions.count == 3) }
            if name.hasPrefix("source-") {
                model.activities = []; model.observedCodexConversations = ["source-example"]
                model.titles["source-example"] = "Review the project changes"
                if name != "source-state-unavailable" {
                    model.sourceApprovalConversations = ["source-example"]; model.needsSourceApproval = true
                }
                model.updateSessionPresentation()
                if name == "source-state-unavailable" {
                    precondition(model.sessions.isEmpty && model.observedCodexConversations == ["source-example"])
                } else {
                    precondition(model.sessions.count == 1 && model.sessions.first?.request == nil)
                    precondition(model.sessions.first?.title == "Review the project changes")
                    precondition(model.sessions.first?.status == .needsInput)
                }
                if name == "source-only-retained", let scope = model.sessions.first?.id {
                    let retained = AttentionRequest(key: .init(scope: .init(installation: scope.installation + ":approvals", conversation: scope.conversation), turn: "earlier", nativeID: .integer(7)),
                        owner: "fixture", title: "Earlier native approval", content: .approval(choices: [.init(id: "accept", label: "Allow")]))
                    model.requests = [.init(request: retained, state: .unavailable)]; model.updateSessionPresentation()
                    precondition(model.sessions.count == 1 && model.sessions.first?.status == .needsInput && model.sessions.first?.needsSourceApproval == true)
                }
            }
            if name == "sessions-disconnected" {
                var activity = ActivityStore()
                for entry in model.activities {
                    let epoch = activity.begin(scope: entry.id)
                    activity.observe(.init(scope: entry.id, epoch: epoch, revision: 1, turnID: entry.turnID, phase: entry.phase, attention: .clear))
                    if entry.phase != .running { activity.invalidate(scope: entry.id, epoch: epoch) }
                }
                model.activities = activity.views; model.updateSessionPresentation()
                precondition(model.activities.count == 3 && model.sessions.count == 1 && model.sessions.first?.status == .running)
            }
            if name == "permission-wait-disconnected" {
                let scope = RequestScope(installation: "claude-local-audit:fixture", conversation: "claude-gap")
                var activity = ActivityStore()
                let epoch = activity.begin(scope: scope)
                activity.observe(.init(scope: scope, epoch: epoch, revision: 1, turnID: "turn", phase: .running, attention: .required))
                model.activities = []; model.claudeActivities = activity.views; model.titles[scope.conversation] = "A permission is waiting"
                model.updateSessionPresentation()
                activity.invalidate(scope: scope, epoch: epoch)
                model.claudeActivities = activity.views; model.updateSessionPresentation()
                precondition(model.sessions.count == 1 && model.sessions.first?.status == .unknown && model.menuBarState.needsInput == 1)
            }
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
        try await renderNotchVariants(model: model, output: output)
        try await verifyNotchInteraction(model: model)
        try await verifyNotchExpansionLayout(model: model)
        for long in [false, true] {
            await model.loadDemo(.approval)
            guard let original = await model.core.snapshot().first(where: { $0.id == model.selectedRequestID })?.request else { throw Failure.render }
            let prefix = long ? ["example-tool"] + Array(repeating: "--example=a value with spaces", count: 40) : ["/usr/bin/printf", "example\\n"]
            let approval = AttentionRequest(key: original.key, owner: original.owner, title: original.title,
                content: original.content, approvalDetails: .init(subject: original.approvalDetails!.subject,
                    persistentActions: ["rule": .commandRule(prefix: prefix)]))
            let epoch = await model.core.begin(scope: approval.key.scope)
            await model.core.observe(.init(scope: approval.key.scope, epoch: epoch, revision: 1, requests: [approval]))
            guard let fixture = await model.core.snapshot().first(where: { $0.id == approval.key }) else { throw Failure.render }
            var review = ApprovalReview(); _ = review.select("rule", in: approval, state: .pending)
            var measured: CGFloat = 0, actions: CGFloat = 0
            let reviewRoot = SingleRequestView(view: fixture, draft: .constant(QuestionDraft()), answer: { _ in }, review: review)
                .font(.system(size: 13)).padding(.top, 16)
                .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .dark)
                .onPreferenceChange(PanelContentHeights.self) { values in
                    measured = values.values.reduce(17, +); actions = values[.actions] ?? 0
                }
            let width: CGFloat = long ? 340 : 420
            let reviewHost = NSHostingView(rootView: reviewRoot); reviewHost.sizingOptions = []
            let reviewWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            reviewWindow.isReleasedWhenClosed = false; reviewWindow.contentView = reviewHost
            reviewWindow.appearance = NSAppearance(named: .darkAqua)
            _ = try await settleHeight(window: reviewWindow, host: reviewHost, width: width, measured: { measured })
            guard actions > 0, actions < 100, !long || abs(reviewHost.bounds.height - 640) <= 1 else { throw Failure.dimensions }
            guard let bitmap = reviewHost.bitmapImageRepForCachingDisplay(in: reviewHost.bounds) else { throw Failure.render }
            reviewHost.cacheDisplay(in: reviewHost.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure.render }
            let name = long ? "approval-rule-review-long" : "approval-rule-review"
            try png.write(to: output.appendingPathComponent(name + ".png"))
            print("\(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh); fixed actions: \(actions)")
            reviewWindow.close()
        }
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
        try await verifyAutomaticClosing(model: model)
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
