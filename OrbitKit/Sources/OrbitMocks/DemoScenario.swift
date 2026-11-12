import Foundation
import OrbitCore

// Named failure and edge states layered over the simulated Spotify, so every UI state can be shown and
// screenshotted without a real account: signed out, Automation denied, Spotify closed, nothing playing, rate
// limited, an empty library and playlist switches that fail.
public enum DemoScenario: String, CaseIterable, Sendable {
    case signedOut = "signed-out"
    case automationDenied = "automation-denied"
    case spotifyClosed = "spotify-closed"
    case idle
    case rateLimited = "rate-limited"
    case emptyLibrary = "empty-library"
    case switchFails = "switch-fails"
    // First launch: Spotify is open, macOS has not asked about Automation yet and no account is connected, so
    // Orbit knows nothing about playback until the user allows it.
    case automationNotAsked = "automation-not-asked"
    // Automation not asked yet, but signed in, so the Web API still shows what plays and the player asks inline.
    case automationNotAskedPlaying = "automation-not-asked-playing"
    case paused

    public struct Services: Sendable {
        public let localPlayer: any LocalPlayer
        public let api: any SpotifyAPI
        public let authorizer: any Authorizer
    }

    public func services() async -> Services {
        await Task.detached(priority: .userInitiated) { MockArtwork.render(MockFixtures.artwork) }.value
        let spotify = MockSpotify()
        let signedOut = self == .signedOut || self == .automationNotAsked
        let authorizer = MockAuthorizer(restoredState: signedOut ? .signedOut : .signedIn)
        let localPlayer = MockLocalPlayer(spotify: spotify)
        switch self {
        case .automationDenied: await spotify.setAutomationPermission(.denied)
        case .automationNotAsked, .automationNotAskedPlaying: await spotify.setAutomationPermission(.notDetermined)
        case .spotifyClosed: await spotify.simulateQuit()
        case .paused: await spotify.setPlaying(false)
        // The desktop app is this Mac's active device, so a switch goes over AppleScript first. Spotify accepts the
        // command and never starts the playlist, the way it silently refuses a context, so the switch fails on
        // confirmation; a Web API switch fails outright below.
        case .switchFails: await spotify.ignorePlayCommands(true)
        default: break
        }
        await spotify.startClock()
        return Services(
            localPlayer: self == .idle ? IdleLocalPlayer(base: localPlayer) : localPlayer,
            api: ScenarioSpotifyAPI(base: MockSpotifyAPI(spotify: spotify), authorizer: authorizer, scenario: self),
            authorizer: authorizer
        )
    }
}

// Spotify running with nothing loaded: no track, stopped, and every command refused.
struct IdleLocalPlayer: LocalPlayer {
    let base: MockLocalPlayer

    func isInstalled() async -> Bool { true }
    func isRunning() async -> Bool { true }
    func automationPermission(prompting: Bool) async -> AutomationPermission { .granted }
    func events() -> AsyncStream<LocalPlayerEvent> { base.events() }
    func state() async throws(OrbitError) -> LocalPlayerState { LocalPlayerState(status: .stopped) }
    func play() async throws(OrbitError) { throw .noActiveDevice }
    func pause() async throws(OrbitError) { throw .noActiveDevice }
    func playPause() async throws(OrbitError) { throw .noActiveDevice }
    func nextTrack() async throws(OrbitError) { throw .noActiveDevice }
    func previousTrack() async throws(OrbitError) { throw .noActiveDevice }
    func play(track: SpotifyURI, inContext context: SpotifyURI?) async throws(OrbitError) {
        try await base.play(track: track, inContext: context)
    }
    func setPosition(_ seconds: TimeInterval) async throws(OrbitError) { throw .noActiveDevice }
    func setVolume(_ percent: Int) async throws(OrbitError) { throw .noActiveDevice }
    func setShuffling(_ enabled: Bool) async throws(OrbitError) { throw .noActiveDevice }
    func setRepeating(_ enabled: Bool) async throws(OrbitError) { throw .noActiveDevice }
}

struct ScenarioSpotifyAPI: SpotifyAPI {
    let base: MockSpotifyAPI
    let authorizer: MockAuthorizer
    let scenario: DemoScenario

    private func authorized() async throws(OrbitError) {
        guard await authorizer.currentState() == .signedIn else { throw .notSignedIn }
    }

    private func libraryRead() async throws(OrbitError) {
        try await authorized()
        if scenario == .rateLimited { throw .rateLimited(retryAfter: 30) }
    }

    func currentUser() async throws(OrbitError) -> UserProfile {
        try await authorized()
        return try await base.currentUser()
    }

    func playlists(_ page: PageRequest) async throws(OrbitError) -> Page<Playlist> {
        try await libraryRead()
        if scenario == .emptyLibrary { return Page(items: [], offset: 0, total: 0, hasMore: false) }
        return try await base.playlists(page)
    }

    func playlistItems(playlistID: String, page: PageRequest) async throws(OrbitError) -> Page<Track> {
        try await libraryRead()
        return try await base.playlistItems(playlistID: playlistID, page: page)
    }

    func savedTracks(_ page: PageRequest) async throws(OrbitError) -> Page<Track> {
        try await libraryRead()
        if scenario == .emptyLibrary { return Page(items: [], offset: 0, total: 0, hasMore: false) }
        return try await base.savedTracks(page)
    }

    func search(_ query: String, categories: Set<SearchCategory>, page: PageRequest) async throws(OrbitError) -> SearchResults {
        try await libraryRead()
        return try await base.search(query, categories: categories, page: page)
    }

    func playbackState() async throws(OrbitError) -> PlaybackSnapshot? {
        try await authorized()
        if scenario == .idle { return nil }
        return try await base.playbackState()
    }

    func devices() async throws(OrbitError) -> [PlaybackDevice] {
        try await libraryRead()
        return try await base.devices()
    }

    func transferPlayback(to deviceID: String, play: Bool) async throws(OrbitError) {
        try await authorized()
        try await base.transferPlayback(to: deviceID, play: play)
    }

    func play(_ target: PlayTarget, deviceID: String?) async throws(OrbitError) {
        try await authorized()
        if scenario == .switchFails, case .context = target {
            try? await Task.sleep(for: .milliseconds(600))
            throw .network(detail: "Simulated failure")
        }
        try await base.play(target, deviceID: deviceID)
    }

    func resume(deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.resume(deviceID: deviceID)
    }

    func pause(deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.pause(deviceID: deviceID)
    }

    func skipToNext(deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.skipToNext(deviceID: deviceID)
    }

    func skipToPrevious(deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.skipToPrevious(deviceID: deviceID)
    }

    func seek(to position: TimeInterval, deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.seek(to: position, deviceID: deviceID)
    }

    func setVolume(_ percent: Int, deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.setVolume(percent, deviceID: deviceID)
    }

    func setShuffle(_ enabled: Bool, deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.setShuffle(enabled, deviceID: deviceID)
    }

    func setRepeat(_ mode: RepeatMode, deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.setRepeat(mode, deviceID: deviceID)
    }

    func queue() async throws(OrbitError) -> PlaybackQueue {
        try await libraryRead()
        if scenario == .emptyLibrary { return PlaybackQueue(current: try await base.queue().current) }
        return try await base.queue()
    }

    func addToQueue(_ uri: SpotifyURI, deviceID: String?) async throws(OrbitError) {
        try await authorized()
        try await base.addToQueue(uri, deviceID: deviceID)
    }

    func libraryContains(_ uris: [SpotifyURI]) async throws(OrbitError) -> Set<SpotifyURI> {
        try await authorized()
        return try await base.libraryContains(uris)
    }

    func saveToLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        try await authorized()
        try await base.saveToLibrary(uris)
    }

    func removeFromLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        try await authorized()
        try await base.removeFromLibrary(uris)
    }
}
