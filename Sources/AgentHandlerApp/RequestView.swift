import SwiftUI
import AppKit
import AgentHandlerCore

struct HandlerPanelView: View {
    @ObservedObject var model: AppModel
    let expanded: Bool
    let toggle: () -> Void
    @State private var selected: RequestKey?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack {
                    Circle().fill(model.requests.isEmpty ? .gray : .orange).frame(width: 6, height: 6)
                    Text(model.demo ? "Agent Handler · Demo" : "Agent Handler").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Text("\(model.requests.count)").font(.system(size: 12, weight: .semibold, design: .monospaced))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse Agent Handler" : "Expand Agent Handler")
            if expanded {
                HStack {
                    Text(model.health).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    Spacer()
                    Button { model.showSettings.toggle() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
                if let issue = model.issue {
                    Text(issue).font(.caption).foregroundStyle(.orange)
                    Button("Dismiss message") { model.issue = nil }.font(.caption)
                }
                if model.showSettings { settings }
                else if model.requests.isEmpty {
                    Spacer(); Text("Nothing needs your attention").frame(maxWidth: .infinity).foregroundStyle(.secondary); Spacer()
                } else {
                    if model.requests.count > 1 {
                        Picker("Request", selection: Binding(get: { current?.id }, set: { selected = $0 })) {
                            ForEach(model.requests) { view in Text(view.request.title).lineLimit(1).tag(Optional(view.id)) }
                        }.labelsHidden()
                    }
                    if let current {
                        Text(model.titles[current.id.scope.conversation] ?? current.id.scope.conversation).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        SingleRequestView(view: current, answer: { model.respond(current.request, answer: $0) })
                            .id(current.request.fingerprint)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Button("Open in source") { model.openSource() }.disabled(model.demo)
                    Spacer()
                    if model.demo { Button("Reset demo") { Task { await model.loadDemo() } } }
                }.font(.caption)
            }
        }.padding(expanded ? 16 : 8).foregroundStyle(.white).background(.black)
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 18 : 12))
            .environment(\.colorScheme, .dark)
    }
    private var current: RequestView? { model.requests.first { $0.id == selected } ?? model.requests.first }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Connect to Desktop questions", isOn: $model.enabled).disabled(model.demo)
            Text("Watches up to 16 recent local conversations. Approval integrations are not enabled in this version.").font(.caption).foregroundStyle(.secondary)
            Picker("Display", selection: $model.displayID) {
                Text("Main display").tag("automatic")
                ForEach(NSScreen.screens, id: \.localizedName) { screen in
                    Text(screen.localizedName).tag(String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? ""))
                }
            }
            Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })).disabled(model.demo)
            Text("Additional conversation IDs").font(.caption)
            TextField("One or more thread IDs", text: $model.extraThreads).textFieldStyle(.roundedBorder).disabled(model.demo)
            Text("The source app keeps control. Unsupported or uncertain requests are handled there.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

private struct SingleRequestView: View {
    let view: RequestView
    let answer: (UserAnswer) -> Void
    @State private var text = ""
    @State private var choice: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(view.request.title).font(.system(size: 15, weight: .medium)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if view.state != .pending { Text(status).font(.caption).foregroundStyle(.orange) }
                switch view.request.content {
                case .question(let options, let allowsText):
                    ForEach(options, id: \.id) { option in
                        Button { choice = option.id; text = "" } label: {
                            HStack(alignment: .top) { Image(systemName: choice == option.id ? "largecircle.fill.circle" : "circle"); Text(option.label).multilineTextAlignment(.leading); Spacer() }
                        }.buttonStyle(.plain).disabled(view.state != .pending)
                    }
                    if allowsText {
                        TextField(options.isEmpty ? "Your answer" : "Or write an answer", text: $text, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(2...6).onChange(of: text) { _, value in if !value.isEmpty { choice = nil } }
                            .disabled(view.state != .pending)
                    }
                    Button(view.state == .sending ? "Sending…" : "Send answer") {
                        if let choice { answer(.option(choice)) } else { answer(.text(text)) }
                    }.buttonStyle(.borderedProminent).disabled(view.state != .pending || (choice == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || text.utf8.count > 16_384)
                case .approval(let choices):
                    ForEach(choices, id: \.id) { choice in Button(choice.label) { answer(.decision(choice.id)) }.disabled(view.state != .pending) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var status: String {
        switch view.state {
        case .sending: "Waiting for the source app to confirm…"
        case .uncertain: "Delivery is uncertain. Continue in the source app; this answer will not be resent."
        case .unavailable, .rejected: "Source state is unavailable. Continue in the source app."
        default: "Request ended."
        }
    }
}
