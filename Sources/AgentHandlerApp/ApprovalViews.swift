import SwiftUI
import AgentHandlerCore

struct ApprovalDetailsView: View {
    let details: ApprovalDetails
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch details.subject {
            case .command(let command, let directory, let reason):
                Text("Run command?").font(.system(size: 17, weight: .semibold))
                if let reason, !reason.isEmpty {
                    Text(reason).font(.system(size: 13)).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Command", systemImage: "terminal").font(.caption).foregroundStyle(.secondary)
                    ApprovalCode(text: command)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Label("Folder", systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                    Text(directory).font(.system(size: 11)).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            case .access(let message, let label, let target, let notices, let technical):
                Text(label == "App" ? "Allow app access?" : "Allow website access?")
                    .font(.system(size: 17, weight: .semibold))
                Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                    Text(notice).font(.system(size: 12)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !target.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label).font(.caption).foregroundStyle(.secondary)
                        ApprovalCode(text: target)
                    }
                }
                DisclosureGroup("Request details") { ApprovalCode(text: technical).padding(.top, 8) }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ApprovalActionsView: View {
    let request: AttentionRequest
    let state: RequestState
    let answer: (UserAnswer) -> Void
    @Binding var review: ApprovalReview

    var body: some View {
        if case .approval(let choices) = request.content {
            if let id = review.choiceID, let persistent = request.approvalDetails?.persistentActions[id] {
                HStack(spacing: 10) {
                    Button("Back") { review.dismiss() }.buttonStyle(.bordered).handlerFocusRing()
                    Spacer(minLength: 0)
                    Button {
                        if let value = review.confirm(in: request, state: state) { answer(value) }
                    } label: { Text(persistent.confirmTitle) }
                        .buttonStyle(.bordered).handlerFocusRing().disabled(state != .pending)
                }.controlSize(.regular)
            } else {
                VStack(spacing: 8) {
                    ForEach(choices, id: \.id) { choice in
                        let persistent = request.approvalDetails?.persistentActions[choice.id]
                        Button {
                            if let value = review.select(choice.id, in: request, state: state) { answer(value) }
                        } label: {
                            HStack {
                                Text(actionTitle(choice, persistent: persistent))
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if persistent != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(ApprovalButtonStyle()).handlerFocusRing().disabled(state != .pending)
                    }
                }
            }
        }
    }

    private func actionTitle(_ choice: ResponseOption, persistent: ApprovalDetails.PersistentAction?) -> String {
        switch persistent {
        case .commandRule: "Allow and save rule…"
        case .savedPermission: "Always allow…"
        case nil: choice.label
        }
    }
}

struct ApprovalPersistentDetailsView: View {
    let action: ApprovalDetails.PersistentAction
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch action {
            case .commandRule(let prefix):
                Text("Save a command rule?").font(.system(size: 13, weight: .semibold))
                Text("Matching commands may run without asking again.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Exact command prefix").font(.caption).foregroundStyle(.secondary)
                ApprovalCode(text: encodedPrefix(prefix))
            case .savedPermission:
                Text("Save this permission?").font(.system(size: 13, weight: .semibold))
                Text("Allow future requests without asking again.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.18)) }
    }
    private func encodedPrefix(_ prefix: [String]) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(prefix)) ?? Data(), as: UTF8.self)
    }
}

private extension ApprovalDetails.PersistentAction {
    var confirmTitle: String {
        switch self { case .commandRule: "Allow and save rule"; case .savedPermission: "Always allow" }
    }
}

private struct ApprovalCode: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ApprovalButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(contrast == .increased ? 0.55 : 0.16)) }
            .contentShape(RoundedRectangle(cornerRadius: 8)).opacity(enabled ? 1 : 0.45)
    }
}
