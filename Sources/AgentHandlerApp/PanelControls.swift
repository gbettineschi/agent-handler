import AppKit
import SwiftUI

struct PanelIconButton: View {
    let title: String
    let symbol: String
    var helpText: String? = nil
    var subtle = false
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: subtle ? 9 : 12, weight: subtle ? .regular : .medium))
                .frame(width: 28, height: 28).contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).focused($focused).focusEffectDisabled()
        .foregroundStyle(subtle ? Color.secondary.opacity(hovered || focused ? 1 : 0.75) : Color.primary)
        .background(.white.opacity(hovered ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2) }
        .onHover { hovered = $0 }
        .accessibilityLabel(title).help(helpText ?? title)
    }
}

private struct HandlerFocusRing: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).focusEffectDisabled().overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
extension View {
    func handlerFocusRing() -> some View { modifier(HandlerFocusRing()) }
}
