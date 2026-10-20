import Foundation

enum PanelPlacement {
    static func menuFrame(visible: CGRect, anchor: CGRect?, contentHeight: CGFloat) -> CGRect {
        let width = min(420, max(1, visible.width - 16))
        let height = min(max(1, contentHeight), 640, max(1, visible.height - 16))
        let x = min(max((anchor?.maxX ?? visible.maxX) - width, visible.minX + 8), visible.maxX - width - 8)
        let top = min(anchor?.minY ?? visible.maxY, visible.maxY) - 6
        return CGRect(x: x, y: max(visible.minY + 8, top - height), width: width, height: height)
    }

}
