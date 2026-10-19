import Foundation
import Testing
@testable import AgentHandlerApp

struct PlacementTests {
    @Test func staysOnChosenScreenBelowNotch() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1048)
        let panel = PanelPlacement.frame(screen: screen, visible: visible, safeTop: 32, expanded: true)
        #expect(panel.width == 420)
        #expect(panel.midX == screen.midX)
        #expect(panel.maxY <= screen.maxY - 32)
        #expect(visible.contains(panel))
    }
    @Test func fitsSmallNonNotchedDisplay() {
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let panel = PanelPlacement.frame(screen: frame, visible: frame, safeTop: 0, expanded: true)
        #expect(frame.contains(panel))
        #expect(panel.width > 0 && panel.height > 0)
    }

    @Test func compactAndShortContentKeepTheSameTopAnchor() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 60, width: 1512, height: 890)
        let compact = PanelPlacement.frame(screen: screen, visible: visible, safeTop: 32, expanded: false)
        let empty = PanelPlacement.frame(screen: screen, visible: visible, safeTop: 32, expanded: true, contentHeight: 230)
        #expect(compact.maxY == empty.maxY)
        #expect(empty.height == 230)
        #expect(visible.contains(empty))
        let long = PanelPlacement.frame(screen: screen, visible: visible, safeTop: 32, expanded: true, contentHeight: 2000)
        #expect(visible.contains(long))
    }
}
