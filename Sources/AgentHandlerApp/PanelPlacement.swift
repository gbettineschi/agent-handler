import Foundation

enum PanelPlacement {
    // Includes a compact Ice bar immediately below the system menu bar.
    private static let menuBandDepth: CGFloat = 64
    private static let gap: CGFloat = 6
    static func isUsableAnchor(_ anchor: CGRect, screen: CGRect, visible: CGRect) -> Bool {
        [anchor.minX, anchor.minY, anchor.width, anchor.height].allSatisfy(\.isFinite) &&
            anchor.width > 0 && anchor.height > 0 && screen.contains(anchor) &&
            anchor.minY >= visible.maxY - menuBandDepth
    }

    static func menuFrame(visible: CGRect, anchor: CGRect?, contentHeight: CGFloat,
                          screenBounds: CGRect? = nil, previousFrame: CGRect? = nil) -> CGRect {
        let bounds = screenBounds ?? CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height + menuBandDepth)
        let usable = anchor.flatMap { isUsableAnchor($0, screen: bounds, visible: visible) ? $0 : nil }
        let previous = previousFrame.flatMap {
            visible.intersects($0) && $0.maxY >= visible.maxY - menuBandDepth - gap ? $0 : nil
        }
        let width = min(420, max(1, visible.width - 16))
        let desiredX = usable.map { $0.midX - width / 2 } ?? previous?.minX ?? (visible.maxX - width - 8)
        let x = min(max(desiredX, visible.minX + 8), visible.maxX - width - 8)
        let top = min(usable.map { $0.minY - gap } ?? previous?.maxY ?? (visible.maxY - gap), visible.maxY - gap)
        let height = min(max(1, contentHeight), 640, max(1, top - visible.minY - 8))
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

}
