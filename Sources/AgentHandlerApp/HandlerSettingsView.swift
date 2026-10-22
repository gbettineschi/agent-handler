import AppKit
import SwiftUI

struct HandlerSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance").font(.headline)
                    Picker("Show Agent Handler in", selection: $model.companionStyle) {
                        ForEach(CompanionStyle.allCases) { style in Text(style.title).tag(style) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Agent Handler location")
                    Text(model.companionStyle == .notch
                        ? model.notchAvailable
                            ? "Hover to preview; move away to fold. Click to keep it open. Escape closes the focused panel. The number shows running agents."
                            : "The notch display is unavailable. Using the menu bar until it returns."
                        : "Click the agent in the menu bar to open. Works with Ice.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tracking").font(.headline)
                    Toggle("Connect to Desktop", isOn: $model.enabled).disabled(model.demo)
                    Text("Questions and supported approvals from recent local Work conversations.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Open automatically").font(.headline)
                    Toggle("Blocking questions or approvals", isOn: $model.autoOpenSettings.blocking).disabled(model.demo)
                    Toggle("When a session finishes", isOn: $model.autoOpenSettings.finished).disabled(model.demo)
                        .help("Includes completion, failure and cancellation. Existing history does not trigger an opening.")
                    Toggle("Non-blocking questions", isOn: $model.autoOpenSettings.nonBlocking).disabled(model.demo)
                    Text("Codex questions are non-blocking. Automatic opens keep keyboard focus in your current app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Startup").font(.headline)
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).disabled(model.demo)
                    Text("Escape or click outside to close. Drafts stay until their request ends. Control-click the agent for commands.").font(.caption).foregroundStyle(.secondary)
                }
                Text("The notch number shows running agents. The menu-bar number also includes requests and recent finishes. Finished rows disappear after five minutes, or you can hide them with ×. New activity brings them back.").font(.caption).foregroundStyle(.secondary)
                Divider()
                DisclosureGroup("Connection details") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.health).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("Claude local audits are read-only. Regular Chat is not tracked.").font(.caption).foregroundStyle(.secondary)
                        TextField("Additional conversation IDs", text: $model.extraThreads).textFieldStyle(.roundedBorder).disabled(model.demo)
                            .accessibilityLabel("Additional conversation IDs")
                    }.padding(.top, 8)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).panelMeasuredHeight(.content)
        }.scrollBounceBehavior(.basedOnSize)
    }
}
