import AppKit
import Combine

@main struct AgentHandlerApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var panel: MenuBarPanel?
    private var item: NSStatusItem?
    private var observations = Set<AnyCancellable>()
    private var animation: Task<Void, Never>?
    private var frame = 0
    private let contextMenu = NSMenu()
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel(demo: CommandLine.arguments.contains("--demo"))
            self.model = model
            panel = MenuBarPanel(model: model)
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.item = item
            item.autosaveName = "AgentHandler.Status"
            if let button = item.button {
                button.imagePosition = .imageLeading
                button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
                button.target = self; button.action = #selector(statusClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                panel?.anchor = button
            }
            for (title, action, key) in [("Open Agent Handler", #selector(openPanel), ""), ("Settings…", #selector(settings), ","), ("Quit Agent Handler", #selector(quit), "q")] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; contextMenu.addItem(entry)
            }
            let main = NSMenu(), appMenu = NSMenuItem()
            appMenu.submenu = contextMenu.copy() as? NSMenu
            main.addItem(appMenu); NSApp.mainMenu = main
            model.attentionChanged = { [weak self] in self?.refreshStatus() }
            model.objectWillChange.sink { [weak self] in
                Task { @MainActor in self?.refreshStatus() }
            }.store(in: &observations)
            refreshStatus()
            model.autoOpenRequested = { [weak self] target in self?.panel?.showAutomatically(for: target) }
            panel?.visibilityChanged = { [weak self] visible in self?.item?.button?.highlight(visible) }
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            model.start()
            if CommandLine.arguments.contains("--show") { panel?.show() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Agent Handler could not start"
            alert.informativeText = "Another instance may already be running, or its private data directory is unavailable."
            alert.runModal(); NSApp.terminate(nil)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { panel?.show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func refreshStatus() {
        guard let model, let item else { return }
        panel?.refresh()
        let visible = panel?.effectiveStyle != .notch
        if item.isVisible != visible {
            item.isVisible = visible
            Task { @MainActor [weak self] in self?.panel?.refresh() }
        }
        guard let button = item.button else { return }
        let state = model.menuBarState
        button.title = " \(state.count)"
        button.image = AgentStatusIcon.image(mode: state.mode, frame: frame)
        button.toolTip = state.description + " Click to open; Control-click for commands."
        button.setAccessibilityLabel(state.description)
        button.setAccessibilityIdentifier("agent-handler-status")
        let moving = visible && state.shouldAnimate(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if moving, animation == nil {
            animation = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    self.frame = (self.frame + 1) % 4
                    guard let model = self.model else { return }
                    self.item?.button?.image = AgentStatusIcon.image(mode: model.menuBarState.mode, frame: self.frame)
                }
            }
        } else if !moving {
            animation?.cancel(); animation = nil; frame = 0
            button.image = AgentStatusIcon.image(mode: state.mode)
        }
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            contextMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        } else { panel?.toggle() }
    }
    @objc private func openPanel() { panel?.show() }
    @objc private func settings() { panel?.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() { panel?.refresh() }
    func applicationWillTerminate(_ notification: Notification) { animation?.cancel(); panel?.shutdown() }
}
