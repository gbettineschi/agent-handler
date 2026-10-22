import Foundation

/// Geometry only. The camera gap comes from AppKit's safe-area rectangles;
/// display size or a hard-coded Mac model never supplies a pretend notch.
struct NotchGeometry: Equatable {
    let screen: CGRect
    let visible: CGRect
    let notch: CGRect
    var stripHeight: CGFloat { notch.height + 4 }
    var collapsedFrame: CGRect {
        let width = min(notch.width + 96, screen.width - 16)
        return CGRect(x: notch.midX - width / 2, y: screen.maxY - stripHeight, width: width, height: stripHeight)
    }
    func expandedFrame(contentHeight: CGFloat) -> CGRect {
        let width = min(520, visible.width - 16)
        let height = min(max(1, contentHeight) + stripHeight, 640 + stripHeight, screen.maxY - visible.minY - 8)
        let x = min(max(notch.midX - width / 2, visible.minX + 8), visible.maxX - width - 8)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }
    static func resolve(screen: CGRect, visible: CGRect, safeTop: CGFloat, left: CGRect?, right: CGRect?) -> Self? {
        guard safeTop.isFinite, safeTop > 0, safeTop < screen.height / 2,
              let left, let right,
              [screen, visible, left, right].allSatisfy({ rect in
                  [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
              }), screen.contains(left), screen.contains(right), screen.contains(visible),
              abs(left.maxY - screen.maxY) < 1, abs(right.maxY - screen.maxY) < 1,
              right.minX > left.maxX, right.minX - left.maxX < screen.width / 2 else { return nil }
        return .init(screen: screen, visible: visible,
            notch: CGRect(x: left.maxX, y: screen.maxY - safeTop, width: right.minX - left.maxX, height: safeTop))
    }
}
