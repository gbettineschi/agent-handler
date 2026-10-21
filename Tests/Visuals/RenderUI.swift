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
    /// A native panel owned by this fixture process, with the real controller
    /// and synthetic transport. No source app or personal request is touched.
    @MainActor private static func verifyAutomaticClosing(model: AppModel) async throws {
        await model.loadDemo(.approval)
        model.requests = await model.core.snapshot().filter(\.needsAttention)
        guard let request = model.requests.first?.request else { throw Failure.render }
        let panel = MenuBarPanel(model: model)
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
    @MainActor private static func render() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/ui-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = try AppModel(demo: true)
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
                precondition(model.sessions.count == 1 && model.sessions.first?.request == nil)
                precondition(model.sessions.first?.title == "Review the project changes")
                precondition(model.sessions.first?.status == (name == "source-state-unavailable" ? .unknown : .needsInput))
                if name == "source-only-retained", let scope = model.sessions.first?.id {
                    let retained = AttentionRequest(key: .init(scope: .init(installation: scope.installation + ":approvals", conversation: scope.conversation), turn: "earlier", nativeID: .integer(7)),
                        owner: "fixture", title: "Earlier native approval", content: .approval(choices: [.init(id: "accept", label: "Allow")]))
                    model.requests = [.init(request: retained, state: .unavailable)]; model.updateSessionPresentation()
                    precondition(model.sessions.count == 1 && model.sessions.first?.status == .needsInput && model.sessions.first?.needsSourceApproval == true)
                }
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
