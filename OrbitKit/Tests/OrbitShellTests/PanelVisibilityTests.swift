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

    @Test func aWindowCoveringTheWholeDisplayIsFullscreen() {
        let windows = [WindowSnapshot(ownerPID: 7, layer: 0, bounds: display, alpha: 1)]
        #expect(FullscreenDetection.isCovered(displayBounds: display, by: windows, excluding: ownPID))
    }

    @Test func aZoomedWindowBelowTheMenuBarIsNot() {
        let zoomed = CGRect(x: 0, y: 24, width: 3440, height: 1346)
        let windows = [WindowSnapshot(ownerPID: 7, layer: 0, bounds: zoomed, alpha: 1)]
        #expect(!FullscreenDetection.isCovered(displayBounds: display, by: windows, excluding: ownPID))
    }

    @Test func systemLayersOwnWindowsAndInvisibleWindowsAreIgnored() {
        let windows = [
            WindowSnapshot(ownerPID: 7, layer: 25, bounds: display, alpha: 1),
            WindowSnapshot(ownerPID: ownPID, layer: 0, bounds: display, alpha: 1),
            WindowSnapshot(ownerPID: 8, layer: 0, bounds: display, alpha: 0),
        ]
        #expect(!FullscreenDetection.isCovered(displayBounds: display, by: windows, excluding: ownPID))
    }

    @Test func onlyTheGivenDisplayCounts() {
        let other = CGRect(x: 3440, y: 0, width: 1512, height: 982)
        let windows = [WindowSnapshot(ownerPID: 7, layer: 0, bounds: other, alpha: 1)]
        #expect(!FullscreenDetection.isCovered(displayBounds: display, by: windows, excluding: ownPID))
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
