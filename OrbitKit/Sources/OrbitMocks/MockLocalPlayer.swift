import Foundation
import OrbitCore

public struct MockLocalPlayer: LocalPlayer {
    public let spotify: MockSpotify

    public init(spotify: MockSpotify) {
        self.spotify = spotify
    }

    public func isInstalled() async -> Bool { true }

    public func isRunning() async -> Bool { await spotify.running }

    public func automationPermission(prompting: Bool) async -> AutomationPermission {
        await spotify.permission(prompting: prompting)
    }

    public func connectDeviceName() async -> String? {
        MockFixtures.localDevice.name
    }

    public func events() -> AsyncStream<LocalPlayerEvent> {
        spotify.eventStream()
    }

    public func state() async throws(OrbitError) -> LocalPlayerState {
        try await spotify.localState()
    }

    public func play() async throws(OrbitError) {
        try await spotify.localCommand("play")
        await spotify.setPlaying(true)
    }

    public func pause() async throws(OrbitError) {
        try await spotify.localCommand("pause")
        await spotify.setPlaying(false)
    }

    public func playPause() async throws(OrbitError) {
        try await spotify.localCommand("playpause")
        await spotify.togglePlaying()
    }

    public func nextTrack() async throws(OrbitError) {
        try await spotify.localCommand("next track")
        await spotify.next()
    }

    public func previousTrack() async throws(OrbitError) {
        try await spotify.localCommand("previous track")
        await spotify.previous()
    }

    public func play(track: SpotifyURI, inContext context: SpotifyURI?) async throws(OrbitError) {
        try await spotify.localCommand("play track")
        await spotify.raiseWindow()
        try await spotify.play(track: track, inContext: context)
    }

    public func isShowingWindow() async -> Bool {
        await spotify.isShowingWindow
    }

    public func hide() async {
        await spotify.hideApp()
    }

    public func setPosition(_ seconds: TimeInterval) async throws(OrbitError) {
        try await spotify.localCommand("set player position")
        await spotify.seek(to: seconds)
    }

    public func setVolume(_ percent: Int) async throws(OrbitError) {
        try await spotify.localCommand("set sound volume")
        await spotify.setVolume(percent)
    }

    public func setShuffling(_ enabled: Bool) async throws(OrbitError) {
        try await spotify.localCommand("set shuffling")
        await spotify.setShuffle(enabled)
    }

    public func setRepeating(_ enabled: Bool) async throws(OrbitError) {
        try await spotify.localCommand("set repeating")
        await spotify.setRepeat(enabled ? .context : .off)
    }
}
