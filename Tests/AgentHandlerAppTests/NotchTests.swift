import Foundation
import Testing
@testable import AgentHandlerApp

struct NotchTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 40, width: 1512, height: 904)
    private func geometry(offset: CGPoint = .zero) throws -> NotchGeometry {
        try #require(NotchGeometry.resolve(screen: screen.offsetBy(dx: offset.x, dy: offset.y),
            visible: visible.offsetBy(dx: offset.x, dy: offset.y), safeTop: 38,
            left: CGRect(x: offset.x, y: 944 + offset.y, width: 660, height: 38),
            right: CGRect(x: 852 + offset.x, y: 944 + offset.y, width: 660, height: 38)))
    }
    @Test func collapsedSurfaceTouchesTheDisplayAndLeavesTheCameraSpaceBetweenWings() throws {
        let value = try geometry()
        #expect(value.notch == CGRect(x: 660, y: 944, width: 192, height: 38))
        #expect(value.collapsedFrame.maxY == screen.maxY)
        #expect(value.collapsedFrame.midX == value.notch.midX)
        #expect(value.collapsedFrame.width == value.notch.width + 96)
        #expect(value.stripHeight == 42)
    }
    @Test func expansionAndContentChangesKeepThePhysicalTopAndCenterFixed() throws {
        let value = try geometry()
        let small = value.expandedFrame(contentHeight: 210)
        let large = value.expandedFrame(contentHeight: 500)
        #expect(small.maxY == value.collapsedFrame.maxY)
        #expect(large.maxY == small.maxY)
        #expect(large.midX == small.midX)
        #expect(large.width == 520)
        #expect(large.height - small.height == 290)
        #expect(small.height == 210 + value.stripHeight)
    }
    @Test func largeContentKeepsTheBottomAboveTheDockAndRemainsBounded() throws {
        let value = try geometry(offset: CGPoint(x: -1512, y: 200))
        let frame = value.expandedFrame(contentHeight: 5000)
        #expect(frame.minY >= value.visible.minY + 8)
        #expect(frame.maxY == value.screen.maxY)
        #expect(frame.height <= 640 + value.stripHeight)
        #expect(value.screen.contains(frame))
    }
    @Test func missingOrContradictorySafeAreasDoNotInventANotch() {
        #expect(NotchGeometry.resolve(screen: screen, visible: visible, safeTop: 0, left: nil, right: nil) == nil)
        #expect(NotchGeometry.resolve(screen: screen, visible: visible, safeTop: 38, left: nil, right: nil) == nil)
        #expect(NotchGeometry.resolve(screen: screen, visible: visible, safeTop: .nan,
            left: .zero, right: .zero) == nil)
        #expect(NotchGeometry.resolve(screen: screen, visible: visible, safeTop: 38,
            left: CGRect(x: 0, y: 944, width: 900, height: 38),
            right: CGRect(x: 660, y: 944, width: 852, height: 38)) == nil)
    }
    @Test func presentationPreferenceSurvivesFallbackAndUnknownValuesAreSafe() throws {
        let name = "AgentHandler.NotchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(CompanionStyle.load(from: defaults) == .menuBar)
        CompanionStyle.notch.save(to: defaults)
        let chosen = CompanionStyle.load(from: defaults)
        #expect(chosen.effective(hasNotch: false) == .menuBar)
        #expect(CompanionStyle.load(from: defaults) == .notch)
        #expect(chosen.effective(hasNotch: true) == .notch)
        defaults.set("future-style", forKey: CompanionStyle.preferenceKey)
        #expect(CompanionStyle.load(from: defaults) == .menuBar)
    }
    @Test func hoverRequiresARealDwellAndCancelsOnAPassThrough() {
        var policy = NotchHoverPolicy()
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 0) == nil)
        #expect(policy.update(inside: false, expanded: false, mayCollapse: false, now: 0.05) == nil)
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 1) == nil)
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 1.2) == .expand)
    }
    @Test func hoverExitHasGraceAndReentryCancelsCollapse() {
        var policy = NotchHoverPolicy()
        #expect(policy.update(inside: false, expanded: true, mayCollapse: true, now: 0) == nil)
        #expect(policy.update(inside: true, expanded: true, mayCollapse: true, now: 0.2) == nil)
        #expect(policy.update(inside: false, expanded: true, mayCollapse: true, now: 1) == nil)
        #expect(policy.update(inside: false, expanded: true, mayCollapse: true, now: 1.4) == .collapse)
    }
    @Test func manualDismissDoesNotReopenUntilThePointerLeavesAndReturns() {
        var policy = NotchHoverPolicy()
        policy.dismissed()
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 0) == nil)
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 2) == nil)
        #expect(policy.update(inside: false, expanded: false, mayCollapse: false, now: 3) == nil)
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 4) == nil)
        #expect(policy.update(inside: true, expanded: false, mayCollapse: false, now: 4.2) == .expand)
    }
    @Test func keyboardEditingSettingsAndAutomaticInterventionCannotBeHoverDismissed() {
        var policy = NotchHoverPolicy()
        #expect(policy.update(inside: false, expanded: true, mayCollapse: false, now: 0) == nil)
        #expect(policy.update(inside: false, expanded: true, mayCollapse: false, now: 10) == nil)
        #expect(policy.update(inside: false, expanded: true, mayCollapse: true, now: 11) == nil)
        #expect(policy.update(inside: false, expanded: true, mayCollapse: true, now: 11.4) == .collapse)
    }
}
