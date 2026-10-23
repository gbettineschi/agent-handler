import AppKit
import SwiftUI
import OSLog
import QuartzCore

final class AttentionPanel: NSPanel {
    var dismiss: (() -> Void)?
    var clicked: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismiss?() }
    override func performClose(_ sender: Any?) { dismiss?() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            // Hover/automatic presentation keeps focus in the other app. Once
            // the user clicks, deliver that first click even inside a ScrollView.
            clicked?()
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }
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
    private var awaitingNotchLayout = false
    private enum Opening { case hover, manual, automatic }
    private var opening: Opening?
    private var hoverPolicy = NotchHoverPolicy()
    private var hoverTask: Task<Void, Never>?
    private var lastPointerInside: Bool?
    private var geometry: NotchGeometry?
    private let geometryProvider: (() -> NotchGeometry?)?
    private let pointerLocation: () -> CGPoint
    private static let log = Logger(subsystem: "dev.gbettineschi.agent-handler", category: "Panel")
    var visibilityChanged: ((Bool) -> Void)?
    var effectiveStyle: CompanionStyle { presentation.style }
    var isExpanded: Bool { presentation.expanded }
    weak var anchor: NSStatusBarButton?
    init(model: AppModel, notchGeometry: (() -> NotchGeometry?)? = nil,
         pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.model = model
        geometryProvider = notchGeometry; self.pointerLocation = pointerLocation
        panel = AttentionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Agent Handler"
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        panel.dismiss = { [weak self] in self?.collapse() }
        panel.clicked = { [weak self] in
            guard let self, self.opening == .hover else { return }
            self.opening = .manual; self.autoClose.openedManually()
        }
        // A stable hosting tree preserves drafts while the window is collapsed.
        let host = HoverHostingView(rootView: CompanionSurfaceView(model: model, presentation: presentation,
            open: { [weak self] in self?.show() },
            settings: { [weak self] in self?.showSettings() },
            collapse: { [weak self] in self?.collapse() },
            contentHeightChanged: { [weak self] height in self?.contentSizeChanged(height) }))
        host.pointerChanged = { [weak self] in self?.pointerChanged() }
        // PanelPlacement owns window dimensions. Intrinsic-size propagation can
        // otherwise make a scrollable error state expand the window itself.
        host.sizingOptions = []
        panel.contentView = host
        // Recover an absent view-entry event using pointer geometry. Both
        // event scopes are needed for movement in our window and other apps.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved], handler: { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .mouseMoved { self?.pointerMoved(); return }
                guard let self, event.windowNumber != self.panel.windowNumber else { return }
                self.dismissIfOutside(event)
            }
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .mouseMoved], handler: { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .mouseMoved { self?.pointerMoved(); return }
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
        awaitingNotchLayout = false
        hoverTask?.cancel(); hoverTask = nil; hoverPolicy = NotchHoverPolicy(); opening = nil
        // The hit region changes from the expanded body to the compact strip.
        lastPointerInside = nil
        // Only a pointer remaining over the compact trigger must leave before
        // reopening. A normal hover-exit must allow the very next re-entry.
        if geometry?.collapsedFrame.contains(pointerLocation()) == true { hoverPolicy.dismissed() }
        autoClose.openedManually()
        guard presentation.expanded else { return }
        presentation.expanded = false; model.showSettings = false
        panel.resignKey()
        if presentation.style == .notch { place() }
        else { panel.orderOut(nil) }
        visibilityChanged?(false)
        if automatically { Self.log.notice("Automatically closed panel; visible: \(self.panel.isVisible)") }
    }
    func showAutomatically(for target: AutoOpenTarget) {
        // Do not navigate away from an answer or settings the user has open.
        guard !presentation.expanded else {
            if opening == .hover, !panel.isKeyWindow, !model.showSettings {
                opening = .automatic
                autoClose.openedAutomatically(for: target, sessions: model.sessions)
            } else { autoClose.include(target) }
            return
        }
        switch target {
        case .request(let key):
            guard model.requests.contains(where: { $0.id == key && $0.state == .pending }) else { return }
            model.selectedRequestID = key; model.showSessions = false
        case .sessions, .finished: model.showSessions = true
        }
        model.showSettings = false
        opening = .automatic
        autoClose.openedAutomatically(for: target, sessions: model.sessions)
        present(takingFocus: false)
        Self.log.notice("Automatically opened panel; keyboard focus: \(self.panel.isKeyWindow)")
    }
    func show() {
        opening = .manual
        autoClose.openedManually()
        present(takingFocus: true)
    }
    private func present(takingFocus: Bool) {
        hoverTask?.cancel(); hoverTask = nil
        let wasVisible = panel.isVisible
        if presentation.style == .notch, !presentation.expanded { prepareNotchLayout() }
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
        synchronizeStyle()
        if model.showSettings { opening = .manual; autoClose.openedManually() }
        if autoClose.update(requests: model.requests, sessions: model.sessions, canClose: !menuTracking) {
            collapse(automatically: true)
        } else { place() }
        if presentation.style == .notch { pointerChanged() }
    }
    private func dismissIfOutside(_ event: NSEvent) {
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard presentation.expanded, !menuTracking, !panel.frame.contains(point) else { return }
        collapse()
    }
    @objc private func menuBegan() { menuTracking = true }
    @objc private func menuEnded() { menuTracking = false; pointerChanged() }
    private func contentSizeChanged(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        resizeTask?.cancel()
        // Coalesce preference updates into one resize after SwiftUI finishes layout.
        resizeTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self,
                  self.awaitingNotchLayout || abs(self.contentHeight - height) >= 1 else { return }
            self.contentHeight = height
            self.awaitingNotchLayout = false
            self.place()
        }
    }
    private func place() {
        if presentation.style == .notch, let geometry {
            guard !awaitingNotchLayout else { return }
            panel.hasShadow = presentation.expanded
            let frame = presentation.expanded ? geometry.expandedFrame(contentHeight: contentHeight) : geometry.collapsedFrame
            if presentation.expanded {
                let viewport = CGSize(width: frame.width, height: frame.height - geometry.stripHeight)
                if presentation.contentViewport != viewport { presentation.contentViewport = viewport }
            }
            applyFrame(frame)
            return
        }
        guard presentation.expanded else { return }
        panel.hasShadow = true
        let anchorRect = anchor.flatMap { button -> CGRect? in
            guard !button.isHiddenOrHasHiddenAncestor, let window = button.window, window.isVisible else { return nil }
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let screens = NSScreen.screens
        let anchoredScreen = anchorRect.flatMap { rect in
            screens.first { PanelPlacement.isUsableAnchor(rect, screen: $0.frame, visible: $0.visibleFrame) }
        }
        let screen = anchoredScreen ?? (panel.isVisible ? panel.screen : nil) ?? NSScreen.main ?? screens.first
        guard let screen else { return }
        let frame = PanelPlacement.menuFrame(visible: screen.visibleFrame, anchor: anchoredScreen == nil ? nil : anchorRect,
            contentHeight: contentHeight, screenBounds: screen.frame, previousFrame: panel.isVisible ? placedFrame : nil)
        applyFrame(frame)
    }
    private func applyFrame(_ frame: CGRect) {
        if placedFrame != frame {
            placedFrame = frame
            let animate = panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? (presentation.style == .notch ? 0.22 : 0.14) : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if animate { panel.animator().setFrame(frame, display: true) }
                else { panel.setFrame(frame, display: true) }
            }
        }
    }
    private func prepareNotchLayout() {
        guard let geometry else { return }
        // Lay out the route at its final width and maximum available height.
        // Its natural-height preference starts the reveal with one target frame.
        let frame = geometry.expandedFrame(contentHeight: .greatestFiniteMagnitude)
        resizeTask?.cancel(); resizeTask = nil
        awaitingNotchLayout = true
        presentation.contentViewport = CGSize(width: frame.width, height: frame.height - geometry.stripHeight)
        // A rapid close/reopen may be coalesced into the same SwiftUI tree.
        // Ask for a new layout receipt even if the natural height is unchanged.
        presentation.layoutRevision &+= 1
    }
    private func synchronizeStyle() {
        if let geometryProvider { geometry = geometryProvider() }
        else {
            geometry = NSScreen.screens.compactMap { screen in
                NotchGeometry.resolve(screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                    left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
            }.first
        }
        if model.notchAvailable != (geometry != nil) { model.notchAvailable = geometry != nil }
        let style = model.companionStyle.effective(hasNotch: geometry != nil)
        if let geometry {
            if presentation.cameraWidth != geometry.notch.width { presentation.cameraWidth = geometry.notch.width }
            if presentation.stripHeight != geometry.stripHeight { presentation.stripHeight = geometry.stripHeight }
        }
        guard style != presentation.style else { return }
        hoverTask?.cancel(); hoverTask = nil; hoverPolicy = NotchHoverPolicy()
        lastPointerInside = nil
        awaitingNotchLayout = false
        if style == .notch, presentation.expanded { prepareNotchLayout() }
        presentation.style = style
        placedFrame = nil
        place()
        if style == .notch || presentation.expanded { panel.orderFrontRegardless() }
        else { panel.resignKey(); panel.orderOut(nil) }
    }
    private var pointerIsInside: Bool {
        // During the shrink the native frame is still larger than the trigger.
        // That vanishing body must not start a fresh dwell and reopen itself.
        let trigger = presentation.expanded ? panel.frame : geometry?.collapsedFrame ?? panel.frame
        return trigger.contains(pointerLocation())
    }
    private func pointerMoved() {
        guard presentation.style == .notch, panel.isVisible, pointerIsInside != lastPointerInside else { return }
        // High-rate movement within the same region does not reschedule dwell
        // tasks. The deadline rechecks the current position even after a stop.
        pointerChanged()
    }
    /// Shared native-event path; fixture tests provide only their own pointer
    /// position and geometry, without moving the user's cursor.
    func pointerChanged() {
        hoverTask?.cancel(); hoverTask = nil
        guard presentation.style == .notch, panel.isVisible else { return }
        let inside = pointerIsInside
        lastPointerInside = inside
        let mayCollapse = opening == .hover && !panel.isKeyWindow && !model.showSettings && !menuTracking
        let now = ProcessInfo.processInfo.systemUptime
        switch hoverPolicy.update(inside: inside, expanded: presentation.expanded,
                                  mayCollapse: mayCollapse, now: now) {
        case .expand:
            opening = .hover; autoClose.openedManually(); present(takingFocus: false)
        case .collapse: collapse()
        case nil: break
        }
        if let deadline = hoverPolicy.nextDeadline {
            hoverTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(max(0.01, deadline - ProcessInfo.processInfo.systemUptime))) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.pointerChanged()
            }
        }
    }
    func shutdown() {
        hoverTask?.cancel(); resizeTask?.cancel()
        for monitor in eventMonitors { NSEvent.removeMonitor(monitor) }
        eventMonitors = []
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
    }
}

@MainActor final class PanelPresentation: ObservableObject {
    @Published var expanded = false
    @Published var style: CompanionStyle = .menuBar
    @Published var cameraWidth: CGFloat = 203
    @Published var stripHeight: CGFloat = 39
    @Published var contentViewport = CGSize(width: 520, height: 640)
    @Published var layoutRevision: UInt64 = 0
}

@MainActor private final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var pointerChanged: (() -> Void)?
    private var area: NSTrackingArea?
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(next); area = next
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?() }
    override func mouseExited(with event: NSEvent) { pointerChanged?() }
}
