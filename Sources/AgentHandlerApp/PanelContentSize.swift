import SwiftUI

/// Measure natural content inside scroll views, never their constrained viewport.
/// Separate regions let the window include fixed controls without counting nested
/// content twice. Preference removal also handles routes and banners disappearing.
enum PanelHeightRegion: Hashable {
    case header, issue, sourceApproval, warning, navigation, content, status, actions, undo, footer
}
struct PanelContentHeights: PreferenceKey {
    static let defaultValue: [PanelHeightRegion: CGFloat] = [:]
    static func reduce(value: inout [PanelHeightRegion: CGFloat], nextValue: () -> [PanelHeightRegion: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
extension View {
    func panelMeasuredHeight(_ region: PanelHeightRegion, limit: CGFloat = .greatestFiniteMagnitude) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: PanelContentHeights.self,
                                   value: [region: min(limit, ceil(geometry.size.height))])
        })
    }
}
