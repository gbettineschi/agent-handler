import AppKit
import SwiftUI

final class AttentionPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor final class NotchPanel {
    private let panel: AttentionPanel
    private let model: AppModel
    private var expanded = false
    init(model: AppModel) {
        self.model = model
        panel = AttentionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        render()
    }
    func toggle() { expanded.toggle(); render(); if expanded { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) } }
    func showSettings() { expanded = true; model.showSettings = true; render(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func refresh() { place() }
    private func render() {
        panel.contentView = NSHostingView(rootView: HandlerPanelView(model: model, expanded: expanded, toggle: { [weak self] in self?.toggle() }))
        place()
    }
    private func place() {
        let screen = NSScreen.screens.first { String(describing: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "") == model.displayID } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        panel.setFrame(PanelPlacement.frame(screen: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top, expanded: expanded), display: true)
        if expanded || screen.safeAreaInsets.top > 0 { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}
