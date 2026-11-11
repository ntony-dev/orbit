import AppKit
import OrbitCore

// The one button worth offering next to an error, if any. Errors that only need time (rate limits, quota) or
// that Orbit cannot fix (restricted content) get the error's own hint and no button.
enum RecoveryAction: Equatable {
    case signIn
    case openAutomationSettings
    case openSpotify
    case openDeveloperDashboard
    case retry

    init?(for error: OrbitError) {
        switch error {
        case .notSignedIn, .authExpired, .callbackPortInUse: self = .signIn
        case .automationDenied: self = .openAutomationSettings
        case .spotifyNotRunning: self = .openSpotify
        case .notAllowlisted: self = .openDeveloperDashboard
        case .network, .unexpected, .noActiveDevice: self = .retry
        case .spotifyNotInstalled, .premiumRequired, .rateLimited, .quotaExceeded, .deviceRestricted,
             .contentRestricted, .playlistItemsUnavailable, .missingClientID, .cancelled, .notImplemented:
            return nil
        }
    }

    var title: String {
        switch self {
        case .signIn: "Sign In…"
        case .openAutomationSettings: "Open Automation Settings"
        case .openSpotify: "Open Spotify"
        case .openDeveloperDashboard: "Open Developer Dashboard"
        case .retry: "Try Again"
        }
    }

    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    static let developerDashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    static func openAutomationSettings() {
        NSWorkspace.shared.open(automationSettingsURL)
    }

    // Launched without activation: the point of Orbit is that Spotify's window stays out of the way.
    static func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
