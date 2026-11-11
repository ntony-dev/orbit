import AppKit
import OrbitCore

// Seam for the AppleScript player. Installed/running checks are real; scripting is not implemented yet and fails
// with a typed error instead of pretending to control Spotify.
public struct SpotifyAppleScriptPlayer: LocalPlayer {
    public static let bundleIdentifier = "com.spotify.client"
    private static let unavailable = OrbitError.notImplemented(feature: "Controlling the Spotify app")

    public init() {}

    public func isInstalled() async -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    public func isRunning() async -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    public func automationPermission(prompting: Bool) async -> AutomationPermission {
        .notDetermined
    }

    public func events() -> AsyncStream<LocalPlayerEvent> {
        AsyncStream { $0.finish() }
    }

    public func state() async throws(OrbitError) -> LocalPlayerState { throw Self.unavailable }
    public func play() async throws(OrbitError) { throw Self.unavailable }
    public func pause() async throws(OrbitError) { throw Self.unavailable }
    public func playPause() async throws(OrbitError) { throw Self.unavailable }
    public func nextTrack() async throws(OrbitError) { throw Self.unavailable }
    public func previousTrack() async throws(OrbitError) { throw Self.unavailable }
    public func play(track: SpotifyURI, inContext context: SpotifyURI?) async throws(OrbitError) { throw Self.unavailable }
    public func setPosition(_ seconds: TimeInterval) async throws(OrbitError) { throw Self.unavailable }
    public func setVolume(_ percent: Int) async throws(OrbitError) { throw Self.unavailable }
    public func setShuffling(_ enabled: Bool) async throws(OrbitError) { throw Self.unavailable }
    public func setRepeating(_ enabled: Bool) async throws(OrbitError) { throw Self.unavailable }
}
