import Foundation

enum PanelPlacement {
    static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, expanded: Bool, contentHeight: CGFloat = 480) -> CGRect {
        let width = min(expanded ? 420 : 220, max(1, visible.width - 16))
        let height = min(expanded ? max(1, contentHeight) : 30, max(1, visible.height - 16))
        let top = min(visible.maxY, screen.maxY - safeTop) - 6
        return CGRect(x: min(max(screen.midX - width / 2, visible.minX + 8), visible.maxX - width - 8),
                      y: max(visible.minY + 8, top - height), width: width, height: height)
    }
}
