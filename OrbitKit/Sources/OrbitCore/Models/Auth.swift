public enum AuthState: Hashable, Sendable {
    // Before the stored session has been checked; UI should not flash a sign-in prompt yet.
    case unknown
    case signedOut
    case authorizing
    case signedIn

    public var isSignedIn: Bool { self == .signedIn }
}

public enum AutomationPermission: Hashable, Sendable {
    case granted
    case denied
    case notDetermined
    // macOS can only report Automation consent for a running target.
    case requiresSpotifyRunning
}
