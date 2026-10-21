import AppKit
import SwiftUI
import OSLog

final class AttentionPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func performClose(_ sender: Any?) { dismiss?() }
}

@MainActor final class MenuBarPanel: NSObject {
    private let panel: AttentionPanel
    private let model: AppModel
    private let presentation = PanelPresentation()
    private var eventMonitors: [Any] = []
    private var menuTracking = false
    private var autoClose = AutoClosePolicy()
    private var contentHeight: CGFloat = 260
    private var resizeTask: Task<Void, Never>?
    private var placedFrame: CGRect?
    private static let log = Logger(subsystem: "dev.gbettineschi.agent-handler", category: "Panel")
    var visibilityChanged: ((Bool) -> Void)?
    weak var anchor: NSStatusBarButton?
    init(model: AppModel) {
        self.model = model
        panel = AttentionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.title = "Agent Handler"
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        panel.dismiss = { [weak self] in self?.collapse() }
        // A stable hosting tree preserves drafts while the window is collapsed.
        let host = NSHostingView(rootView: HandlerPanelView(model: model, presentation: presentation,
            collapse: { [weak self] in self?.collapse() },
            contentHeightChanged: { [weak self] height in self?.contentSizeChanged(height) }))
        // PanelPlacement owns window dimensions. Intrinsic-size propagation can
        // otherwise make a scrollable error state expand the window itself.
        host.sizingOptions = []
        panel.contentView = host
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.windowNumber != self.panel.windowNumber else { return }
                self.dismissIfOutside(event)
            }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel, event.window !== self.anchor?.window else { return }
                self.dismissIfOutside(event)
            }
            return event
        }) { eventMonitors.append(monitor) }
    }
    func toggle() {
        if presentation.expanded { collapse() }
        else { show() }
    }
    private func collapse(automatically: Bool = false) {
        autoClose.openedManually()
        guard presentation.expanded else { return }
        presentation.expanded = false; model.showSettings = false
        panel.resignKey(); panel.orderOut(nil)
        visibilityChanged?(false)
        if automatically { Self.log.notice("Automatically closed panel; visible: \(self.panel.isVisible)") }
    }
    func showAutomatically(for target: AutoOpenTarget) {
        // Do not navigate away from an answer or settings the user has open.
        guard !presentation.expanded else { autoClose.include(target); return }
        switch target {
        case .request(let key):
            guard model.requests.contains(where: { $0.id == key && $0.state == .pending }) else { return }
            model.selectedRequestID = key; model.showSessions = false
        case .sessions, .finished: model.showSessions = true
        }
        model.showSettings = false
        autoClose.openedAutomatically(for: target, sessions: model.sessions)
        present(takingFocus: false)
        Self.log.notice("Automatically opened panel; keyboard focus: \(self.panel.isKeyWindow)")
    }
    func show() {
        autoClose.openedManually()
        present(takingFocus: true)
    }
    private func present(takingFocus: Bool) {
        let wasVisible = panel.isVisible
        presentation.expanded = true
        place()
        panel.contentView?.window?.recalculateKeyViewLoop()
        panel.alphaValue = wasVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        if takingFocus { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        visibilityChanged?(true)
        guard !wasVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 1
        }
    }
    func showSettings() { model.showSettings = true; show() }
    func refresh() {
        if model.showSettings { autoClose.openedManually() }
        if autoClose.update(requests: model.requests, sessions: model.sessions, canClose: !menuTracking) {
            collapse(automatically: true)
        } else { place() }
    }
    private func dismissIfOutside(_ event: NSEvent) {
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard presentation.expanded, !menuTracking, !panel.frame.contains(point) else { return }
        collapse()
    }
    @objc private func menuBegan() { menuTracking = true }
    @objc private func menuEnded() { menuTracking = false }
    private func contentSizeChanged(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        resizeTask?.cancel()
        // Coalesce preference updates into one resize after SwiftUI finishes layout.
        resizeTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, abs(self.contentHeight - height) >= 1 else { return }
            self.contentHeight = height
            self.place()
        }
    }
    private func place() {
        guard presentation.expanded else { return }
        let anchorRect = anchor.flatMap { button in button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) } }
        let screen = anchor?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = PanelPlacement.menuFrame(visible: screen.visibleFrame, anchor: anchorRect, contentHeight: contentHeight)
        if placedFrame != frame {
            placedFrame = frame
            let animate = panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? 0.14 : 0
                if animate { panel.animator().setFrame(frame, display: true) }
                else { panel.setFrame(frame, display: true) }
            }
        }
    }
}

@MainActor final class PanelPresentation: ObservableObject {
    @Published var expanded = false
}
