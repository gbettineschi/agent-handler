import AppKit
import SwiftUI

struct HandlerSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tracking").font(.headline)
                    Toggle("Connect to Desktop", isOn: $model.enabled).disabled(model.demo)
                    Text("Questions and supported approvals from recent local Work conversations.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Startup").font(.headline)
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).disabled(model.demo)
                    Text("Escape or click outside to close. Drafts stay until their request ends. Control-click the menu-bar icon for commands.").font(.caption).foregroundStyle(.secondary)
                }
                Text("The menu-bar number includes active sessions and finishes from the last five minutes. Hide finished rows with ×; new activity brings them back.").font(.caption).foregroundStyle(.secondary)
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
