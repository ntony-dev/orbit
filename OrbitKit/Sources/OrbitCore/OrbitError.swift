import Foundation

public enum OrbitError: Error, Hashable, Sendable {
    case spotifyNotInstalled
    case spotifyNotRunning
    case automationDenied
    case notSignedIn
    case authExpired
    // Development Mode apps answer 403 for any account missing from the app's allowlist.
    case notAllowlisted
    case premiumRequired
    case rateLimited(retryAfter: TimeInterval?)
    // Dev-mode quota is shared across the developer's apps; Spotify signals it as 429 with reason QUOTA_EXCEEDED.
    case quotaExceeded(retryAfter: TimeInterval?)
    case noActiveDevice
    case deviceRestricted
    case contentRestricted
    case playlistItemsUnavailable
    case network(detail: String)
    case callbackPortInUse(port: Int)
    case missingClientID
    case cancelled
    // Marks seams whose real implementation has not landed yet, so they fail loudly instead of pretending.
    case notImplemented(feature: String)
    case unexpected(detail: String)

    public var message: String {
        switch self {
        case .spotifyNotInstalled: "Spotify isn't installed on this Mac."
        case .spotifyNotRunning: "Spotify isn't running."
        case .automationDenied: "Orbit isn't allowed to control Spotify."
        case .notSignedIn: "You're not signed in to Spotify."
        case .authExpired: "Your Spotify session has expired."
        case .notAllowlisted: "This Spotify account isn't enabled for this Orbit client."
        case .premiumRequired: "Spotify Premium is required for remote playback control."
        case .rateLimited: "Spotify is limiting requests right now."
        case .quotaExceeded: "This app's Spotify request quota is used up for now."
        case .noActiveDevice: "No Spotify device is active."
        case .deviceRestricted: "This device can't be controlled remotely."
        case .contentRestricted: "This content can't be played here."
        case .playlistItemsUnavailable: "Spotify doesn't share the tracks of playlists you don't own."
        case .network: "Can't reach Spotify."
        case .callbackPortInUse(let port): "Port \(port) is in use, so sign-in can't finish."
        case .missingClientID: "No Spotify Client ID is configured."
        case .cancelled: "Cancelled."
        case .notImplemented(let feature): "\(feature) isn't available in this build yet."
        case .unexpected: "Something went wrong talking to Spotify."
        }
    }

    public var recoveryHint: String? {
        switch self {
        case .spotifyNotInstalled: "Install the Spotify desktop app, then reopen Orbit."
        case .spotifyNotRunning: "Open Spotify to control playback on this Mac."
        case .automationDenied: "Allow Orbit under System Settings › Privacy & Security › Automation › Spotify."
        case .notSignedIn: "Sign in to Spotify from Orbit's settings."
        case .authExpired: "Sign in again to continue."
        case .notAllowlisted: "Ask the app owner to add your account in the Spotify Developer Dashboard, or use your own Client ID."
        case .premiumRequired: "Control playback in the Spotify app on this Mac instead."
        case .rateLimited(let retryAfter), .quotaExceeded(let retryAfter):
            retryAfter.map { "Try again in \(Self.formatted($0))." } ?? "Try again in a little while."
        case .noActiveDevice: "Start playback in Spotify or pick a device."
        case .deviceRestricted: "Choose another device."
        case .contentRestricted: nil
        case .playlistItemsUnavailable: "You can still play the playlist."
        case .network: "Check your internet connection."
        case .callbackPortInUse: "Quit the app using it and try signing in again."
        case .missingClientID: "Add your Spotify Client ID in Orbit's settings."
        case .cancelled, .notImplemented, .unexpected: nil
        }
    }

    public var retryAfter: TimeInterval? {
        switch self {
        case .rateLimited(let retryAfter), .quotaExceeded(let retryAfter): retryAfter
        default: nil
        }
    }

    private static func formatted(_ interval: TimeInterval) -> String {
        Duration.seconds(max(1, interval.rounded(.up)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
    }
}

extension OrbitError: LocalizedError {
    public var errorDescription: String? { message }
    public var recoverySuggestion: String? { recoveryHint }
}
