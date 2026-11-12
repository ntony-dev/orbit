import CoreGraphics
import OrbitCore
@testable import OrbitShell
import Testing

struct RecoveryActionTests {
    @Test func errorsMapToTheirFix() {
        #expect(RecoveryAction(for: .authExpired) == .signIn)
        #expect(RecoveryAction(for: .automationDenied) == .openAutomationSettings)
        #expect(RecoveryAction(for: .spotifyNotRunning) == .openSpotify)
        #expect(RecoveryAction(for: .notAllowlisted) == .openDeveloperDashboard)
        #expect(RecoveryAction(for: .network(detail: "offline")) == .retry)
    }

    @Test func waitingErrorsOfferNoButton() {
        #expect(RecoveryAction(for: .rateLimited(retryAfter: 30)) == nil)
        #expect(RecoveryAction(for: .quotaExceeded(retryAfter: nil)) == nil)
        #expect(RecoveryAction(for: .contentRestricted) == nil)
    }
}

struct LaunchOptionsTests {
    @Test func parsesTestingArguments() {
        let options = LaunchOptions(arguments: ["Orbit", "--demo", "--expanded", "--panel-anchor", "100,200", "--settings", "spotify"])
        #expect(options.usesMocks)
        #expect(options.startsExpanded)
        #expect(options.anchorPoint == CGPoint(x: 100, y: 200))
        #expect(options.settingsPane == .spotify)
    }

    @Test func measurementStatesNeedTheDemo() {
        let demo = LaunchOptions(arguments: ["Orbit", "--demo", "--paused", "--pill-hidden"])
        #expect(demo.startsPaused && demo.startsWithPillHidden)
        let real = LaunchOptions(arguments: ["Orbit", "--paused", "--pill-hidden"])
        #expect(!real.startsPaused && !real.startsWithPillHidden)
    }

    #if DEBUG
    @Test func parsesCaptureArguments() {
        let options = LaunchOptions(arguments: [
            "Orbit", "--demo", "--panel-anchor", "2870,1422", "--panel-anchor-kind", "top", "--morph-every", "8", "--dock-top-center",
        ])
        #expect(options.pinnedAnchor == .topCenter)
        #expect(options.morphPeriod == .seconds(8))
        #expect(options.docksAtTopCenter)
        #expect(LaunchOptions(arguments: ["Orbit", "--panel-anchor-kind", "bottom-trailing"]).pinnedAnchor == .bottomTrailing)
        #expect(LaunchOptions(arguments: ["Orbit", "--panel-anchor-kind", "trailing"]).pinnedAnchor == .centerTrailing)
        #expect(LaunchOptions(arguments: ["Orbit", "--panel-anchor-kind", "middle"]).pinnedAnchor == nil)
        #expect(!LaunchOptions(arguments: ["Orbit", "--dock-top-center"]).docksAtTopCenter)
    }
    #endif

    @Test func settingsWithoutAPaneOpensAppearance() {
        #expect(LaunchOptions(arguments: ["Orbit", "--settings"]).settingsPane == .appearance)
        #expect(LaunchOptions(arguments: ["Orbit"]).settingsPane == nil)
    }
}
