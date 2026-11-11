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

    public func events() -> AsyncStream<LocalPlayerEvent> {
        spotify.eventStream()
    }

    public func state() async throws(OrbitError) -> LocalPlayerState {
        try await spotify.localState()
    }

    public func play() async throws(OrbitError) {
        try await command { await $0.setPlaying(true) }
    }

    public func pause() async throws(OrbitError) {
        try await command { await $0.setPlaying(false) }
    }

    public func playPause() async throws(OrbitError) {
        try await command { await $0.togglePlaying() }
    }

    public func nextTrack() async throws(OrbitError) {
        try await command { await $0.next() }
    }

    public func previousTrack() async throws(OrbitError) {
        try await command { await $0.previous() }
    }

    public func play(track: SpotifyURI, inContext context: SpotifyURI?) async throws(OrbitError) {
        try await spotify.requireRunning()
        await spotify.simulateLatency()
        try await spotify.play(track: track, inContext: context)
    }

    public func setPosition(_ seconds: TimeInterval) async throws(OrbitError) {
        try await command { await $0.seek(to: seconds) }
    }

    public func setVolume(_ percent: Int) async throws(OrbitError) {
        try await command { await $0.setVolume(percent) }
    }

    public func setShuffling(_ enabled: Bool) async throws(OrbitError) {
        try await command { await $0.setShuffle(enabled) }
    }

    public func setRepeating(_ enabled: Bool) async throws(OrbitError) {
        try await command { await $0.setRepeat(enabled ? .context : .off) }
    }

    private func command(_ body: (MockSpotify) async -> Void) async throws(OrbitError) {
        try await spotify.requireRunning()
        await spotify.simulateLatency()
        await body(spotify)
    }
}
