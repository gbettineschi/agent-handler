import Foundation
import Testing
@testable import AgentHandlerApp

struct PlacementTests {
    @Test func anchorsToMenuItemOnNegativeCoordinateScreen() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1048)
        let anchor = CGRect(x: -70, y: 1048, width: 45, height: 32)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: anchor, contentHeight: 480)
        #expect(panel.width == 420)
        #expect(panel.maxX == -8)
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

    @Test func panelCentersUnderItsButtonWhenThereIsSpace() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let anchor = CGRect(x: 700, y: 950, width: 40, height: 32)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: anchor, contentHeight: 300)
        #expect(panel.midX == anchor.midX)
        #expect(panel.maxY == anchor.minY - 6)
    }

    @Test func hiddenIceAnchorFallsBackToTopRightInsteadOfClampingToTheLeft() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let hidden = CGRect(x: -9000, y: 950, width: 40, height: 32)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: hidden, contentHeight: 300)
        #expect(panel.maxX == visible.maxX - 8)
        #expect(panel.maxY == visible.maxY - 6)
    }

    @Test func anchorAwayFromTheMenuBarCannotPlaceThePanelInTheMiddleOfTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let stale = CGRect(x: 700, y: 450, width: 40, height: 32)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: stale, contentHeight: 300)
        #expect(panel.maxY == visible.maxY - 6)
        #expect(panel.maxX == visible.maxX - 8)
    }

    @Test func anOpenPanelKeepsItsTopAndHorizontalPositionWhenIceHidesTheAnchor() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let previous = CGRect(x: 510, y: 644, width: 420, height: 300)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: nil, contentHeight: 480, previousFrame: previous)
        #expect(panel.minX == 510)
        #expect(panel.maxY == 944)
        #expect(panel.height == 480)
    }

    @Test func staleFrameFromANewDisplayArrangementDoesNotBecomeAnAnchor() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let previous = CGRect(x: 510, y: 100, width: 420, height: 300)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: nil, contentHeight: 480, previousFrame: previous)
        #expect(panel.maxX == 1504)
        #expect(panel.maxY == 944)
    }

    @Test func shortDisplayFitsBelowAnIceBarWithoutCoveringItsButton() {
        let visible = CGRect(x: 0, y: 0, width: 400, height: 300)
        let anchor = CGRect(x: 170, y: 260, width: 40, height: 30)
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: anchor, contentHeight: 480)
        #expect(panel.maxY == 254)
        #expect(panel.minY >= 8)
        #expect(visible.contains(panel))
    }

    @Test func menuAnchorUsesTheFullDisplayEvenWhenTheDockReducesTheWorkArea() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 950)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let anchor = CGRect(x: 1480, y: 950, width: 30, height: 32)
        #expect(PanelPlacement.isUsableAnchor(anchor, screen: screen, visible: visible))
        let panel = PanelPlacement.menuFrame(visible: visible, anchor: anchor, contentHeight: 300, screenBounds: screen)
        #expect(panel.maxY == 944)
        #expect(visible.contains(panel))
        #expect(!PanelPlacement.isUsableAnchor(anchor, screen: screen.offsetBy(dx: -1512, dy: 0), visible: visible.offsetBy(dx: -1512, dy: 0)))
    }
}
