import AppKit
import SwiftUI

struct PanelIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28).contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).focused($focused)
        .background(.white.opacity(hovered ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2) }
        .onHover { hovered = $0 }
        .accessibilityLabel(title).help(title)
    }
}

extension NSScreen {
    var handlerDisplayID: String {
        String(describing: deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "")
    }
}
