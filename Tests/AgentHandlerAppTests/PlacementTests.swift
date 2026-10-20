import Foundation
import Testing
@testable import AgentHandlerApp

struct PlacementTests {
    @Test func anchorsToMenuItemOnNegativeCoordinateScreen() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1048)
        let anchor = CGRect(x: -70, y: 1048, width: 45, height: 32)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: anchor, contentHeight: 480)
        #expect(panel.width == 420)
        #expect(panel.maxX == -25)
        #expect(panel.maxY == 1042)
        #expect(visible.contains(panel))
    }
    @Test func fitsSmallDisplayAndOffscreenIceAnchor() {
        let visible = CGRect(x: 0, y: 0, width: 400, height: 300)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: CGRect(x: -9000, y: 320, width: 40, height: 30), contentHeight: 480)
        #expect(visible.contains(panel))
        #expect(panel.width > 0 && panel.height > 0)
    }
    @Test func changingContentHeightPreservesTopAndFallbackIsBounded() {
        let visible = CGRect(x: 0, y: 60, width: 1512, height: 890)
        let short = PanelPlacement.menuFrame(visible: visible, anchor: nil, contentHeight: 230)
        let long = PanelPlacement.menuFrame(visible: visible, anchor: nil, contentHeight: 2000)
        #expect(short.maxY == 944)
        #expect(short.height == 230)
        #expect(long.height == 640)
        #expect(long.maxY == short.maxY)
        #expect(visible.contains(long))
    }
}
