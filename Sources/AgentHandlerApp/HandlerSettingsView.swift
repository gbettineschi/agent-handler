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
                    Text("Appearance & startup").font(.headline)
                    Picker("Display", selection: $model.displayID) {
                        Text("Main display").tag("automatic")
                    ForEach(NSScreen.screens, id: \.handlerDisplayID) { screen in
                            Text(screen.localizedName).tag(screen.handlerDisplayID)
                        }
                    }
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).disabled(model.demo)
                    Text("Click the island to open. Escape or click outside to close. Drafts stay until their request ends.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                DisclosureGroup("Connection details") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.health).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("Claude local audits are read-only. Regular Chat is not tracked.").font(.caption).foregroundStyle(.secondary)
                        TextField("Additional conversation IDs", text: $model.extraThreads).textFieldStyle(.roundedBorder).disabled(model.demo)
                            .accessibilityLabel("Additional conversation IDs")
                    }.padding(.top, 8)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollBounceBehavior(.basedOnSize)
    }
}
