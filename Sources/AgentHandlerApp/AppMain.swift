import AppKit

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
    private var panel: NotchPanel?
    private var item: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel(demo: CommandLine.arguments.contains("--demo"))
            self.model = model
            panel = NotchPanel(model: model)
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.item = item
            let icon = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Agent Handler")
            icon?.isTemplate = true
            item.button?.image = icon
            item.button?.toolTip = "Agent Handler"
            let menu = NSMenu()
            for (title, action, key) in [("Open Agent Handler", #selector(toggle), ""), ("Settings…", #selector(settings), ","), ("Quit Agent Handler", #selector(quit), "q")] {
                let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry)
            }
            item.menu = menu
            model.attentionChanged = { [weak self, weak model] in
                let count = model?.requests.count ?? 0
                self?.item?.button?.title = count == 0 ? "" : " \(count)"
                self?.item?.button?.setAccessibilityLabel("Agent Handler, \(count) requests need attention")
                self?.panel?.refresh()
            }
            model.placementChanged = { [weak self] in self?.panel?.refresh() }
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            model.start()
            if CommandLine.arguments.contains("--show") || model.demo { panel?.toggle() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Agent Handler could not start"
            alert.informativeText = "Another instance may already be running, or its private data directory is unavailable."
            alert.runModal(); NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func toggle() { panel?.toggle() }
    @objc private func settings() { panel?.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func screenChanged() { panel?.refresh() }
}
