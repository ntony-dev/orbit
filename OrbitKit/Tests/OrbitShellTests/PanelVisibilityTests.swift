import CoreGraphics
import OrbitCore
import OrbitEngine
@testable import OrbitShell
import Testing

struct PanelVisibilityTests {
    private let shown = PanelVisibility(
        isPillVisible: true,
        hidesInFullscreen: true,
        isFullscreenAppFrontmost: false,
        hidesWhenSpotifyQuits: true,
        isSpotifyRunning: true,
        isPresentedOnDemand: false
    )

    @Test func showsByDefault() {
        #expect(shown.showsPanel)
    }

    @Test func eachHidingRuleHides() {
        var hidden = shown
        hidden.isPillVisible = false
        #expect(!hidden.showsPanel)

        hidden = shown
        hidden.isFullscreenAppFrontmost = true
        #expect(!hidden.showsPanel)

        hidden = shown
        hidden.isSpotifyRunning = false
        #expect(!hidden.showsPanel)
    }

    @Test func rulesThatAreOffDoNotHide() {
        var visibility = shown
        visibility.hidesInFullscreen = false
        visibility.isFullscreenAppFrontmost = true
        visibility.hidesWhenSpotifyQuits = false
        visibility.isSpotifyRunning = false
        #expect(visibility.showsPanel)
    }

    @Test func openingOnDemandOverridesEveryRule() {
        let visibility = PanelVisibility(
            isPillVisible: false,
            hidesInFullscreen: true,
            isFullscreenAppFrontmost: true,
            hidesWhenSpotifyQuits: true,
            isSpotifyRunning: false,
            isPresentedOnDemand: true
        )
        #expect(visibility.showsPanel)
    }
}

struct FullscreenDetectionTests {
    private let display = CGRect(x: 0, y: 0, width: 3440, height: 1440)
    private let ownPID: pid_t = 42
    private let app: pid_t = 7

    private func context(
        _ display: CGRect? = nil,
        topInset: CGFloat = 0,
        menuBarAutoHides: Bool = false,
        fullscreenApp: pid_t? = nil
    ) -> FullscreenContext {
        FullscreenContext(
            displayBounds: display ?? self.display,
            fullscreenTopInset: topInset,
            menuBarAutoHidesOnDesktop: menuBarAutoHides,
            frontmostFullscreenPID: fullscreenApp
        )
    }

    private func window(_ bounds: CGRect, pid: pid_t = 7, layer: Int = 0, alpha: Double = 1) -> [WindowSnapshot] {
        [WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds, alpha: alpha)]
    }

    @Test func aWindowCoveringTheWholeDisplayIsFullscreen() {
        #expect(FullscreenDetection.isCovered(context(), by: window(display), excluding: ownPID))
    }

    @Test func aZoomedWindowBelowTheMenuBarIsNot() {
        let zoomed = CGRect(x: 0, y: 30, width: 3440, height: 1410)
        #expect(!FullscreenDetection.isCovered(context(), by: window(zoomed), excluding: ownPID))
    }

    // With the menu bar hidden on the desktop and no Dock on this display, zooming fills the whole display.
    @Test func aZoomedWindowUnderAnAutoHidingMenuBarIsNot() {
        #expect(!FullscreenDetection.isCovered(context(menuBarAutoHides: true), by: window(display), excluding: ownPID))
    }

    @Test func theActiveFullscreenAppCountsWhateverTheMenuBarSetting() {
        let covered = context(menuBarAutoHides: true, fullscreenApp: app)
        #expect(FullscreenDetection.isCovered(covered, by: window(display), excluding: ownPID))
    }

    // Full screen windows on a display with a notch start below the camera housing.
    @Test func aFullscreenWindowBelowTheNotchCounts() {
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let belowNotch = CGRect(x: 0, y: 32, width: 1512, height: 950)
        #expect(FullscreenDetection.isCovered(context(laptop, topInset: 32, fullscreenApp: app), by: window(belowNotch), excluding: ownPID))
        #expect(!FullscreenDetection.isCovered(context(laptop, topInset: 32), by: window(belowNotch), excluding: ownPID))
    }

    @Test func aFullscreenWindowBelowAMenuBarKeptVisibleCounts() {
        let belowMenuBar = CGRect(x: 0, y: 30, width: 3440, height: 1410)
        #expect(FullscreenDetection.isCovered(context(topInset: 30, fullscreenApp: app), by: window(belowMenuBar), excluding: ownPID))
    }

    @Test func theActiveFullscreenAppMustSpanThisDisplay() {
        let smaller = CGRect(x: 0, y: 30, width: 1720, height: 1410)
        let tooLow = CGRect(x: 0, y: 200, width: 3440, height: 1240)
        let fullscreen = context(topInset: 30, fullscreenApp: app)
        #expect(!FullscreenDetection.isCovered(fullscreen, by: window(smaller), excluding: ownPID))
        #expect(!FullscreenDetection.isCovered(fullscreen, by: window(tooLow), excluding: ownPID))
        // Only the full screen app gets the inset; another app's zoomed window does not.
        let zoomed = CGRect(x: 0, y: 30, width: 3440, height: 1410)
        #expect(!FullscreenDetection.isCovered(fullscreen, by: window(zoomed, pid: 8), excluding: ownPID))
    }

    @Test func systemLayersOwnWindowsAndInvisibleWindowsAreIgnored() {
        let windows = [
            WindowSnapshot(ownerPID: 7, layer: 25, bounds: display, alpha: 1),
            WindowSnapshot(ownerPID: ownPID, layer: 0, bounds: display, alpha: 1),
            WindowSnapshot(ownerPID: 8, layer: 0, bounds: display, alpha: 0),
        ]
        #expect(!FullscreenDetection.isCovered(context(), by: windows, excluding: ownPID))
        #expect(!FullscreenDetection.isCovered(context(fullscreenApp: ownPID), by: windows, excluding: ownPID))
    }

    @Test func onlyTheGivenDisplayCounts() {
        let other = CGRect(x: 3440, y: 0, width: 1512, height: 982)
        #expect(!FullscreenDetection.isCovered(context(), by: window(other), excluding: ownPID))
        #expect(!FullscreenDetection.isCovered(context(fullscreenApp: app), by: window(other), excluding: ownPID))
    }
}

struct InterfaceVisibilityTests {
    @Test func followsThePanel() {
        #expect(InterfaceVisibility(isPanelVisible: true, isExpanded: false, areScreensAsleep: false) == .collapsed)
        #expect(InterfaceVisibility(isPanelVisible: true, isExpanded: true, areScreensAsleep: false) == .expanded)
    }

    @Test func hiddenWheneverNobodyCanSeeIt() {
        #expect(InterfaceVisibility(isPanelVisible: false, isExpanded: false, areScreensAsleep: false) == .hidden)
        #expect(InterfaceVisibility(isPanelVisible: false, isExpanded: true, areScreensAsleep: false) == .hidden)
        #expect(InterfaceVisibility(isPanelVisible: true, isExpanded: true, areScreensAsleep: true) == .hidden)
    }
}
