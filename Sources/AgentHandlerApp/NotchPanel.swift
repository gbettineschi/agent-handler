import AppKit
import SwiftUI
import Combine

final class AttentionPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func performClose(_ sender: Any?) { dismiss?() }
}

@MainActor final class NotchPanel: NSObject {
    private let panel: AttentionPanel
    private let model: AppModel
    private let presentation = PanelPresentation()
    private var observations = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var menuTracking = false
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
            toggle: { [weak self] in self?.toggle() }, collapse: { [weak self] in self?.collapse() }))
        // PanelPlacement owns window dimensions. Intrinsic-size propagation can
        // otherwise make a scrollable error state expand the window itself.
        host.sizingOptions = []
        panel.contentView = host
        model.$showSettings.combineLatest(model.$requests, model.$selectedRequestID).sink { [weak self] _, _, _ in
            Task { @MainActor [weak self] in self?.place() }
        }.store(in: &observations)
        model.$activities.combineLatest(model.$claudeActivities).sink { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.place() }
        }.store(in: &observations)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.windowNumber != self.panel.windowNumber else { return }
                self.dismissIfOutside(event)
            }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                self.dismissIfOutside(event)
            }
            return event
        }) { eventMonitors.append(monitor) }
        place()
    }
    func toggle() {
        if presentation.expanded { collapse() }
        else { presentation.expanded = true; place(); panel.makeKeyAndOrderFront(nil) }
    }
    private func collapse() {
        guard presentation.expanded else { return }
        presentation.expanded = false; model.showSettings = false
        panel.resignKey(); place()
    }
    func showSettings() { presentation.expanded = true; model.showSettings = true; place(); panel.makeKeyAndOrderFront(nil) }
    func refresh() { place() }
    private func dismissIfOutside(_ event: NSEvent) {
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard presentation.expanded, !menuTracking, !panel.frame.contains(point) else { return }
        collapse()
    }
    @objc private func menuBegan() { menuTracking = true }
    @objc private func menuEnded() { menuTracking = false }
    private func place() {
        let screen = NSScreen.screens.first { $0.handlerDisplayID == model.displayID } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let approval: Bool
        if let content = model.displayedRequest?.request.content, case .approval = content { approval = true } else { approval = false }
        let height: CGFloat = model.showSettings || approval ? 480 : (model.requests.isEmpty && model.sessions.isEmpty ? 260 : 400)
        panel.setFrame(PanelPlacement.frame(screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                                           expanded: presentation.expanded, contentHeight: height), display: true)
        panel.orderFrontRegardless()
    }
}

@MainActor final class PanelPresentation: ObservableObject {
    @Published var expanded = false
}
