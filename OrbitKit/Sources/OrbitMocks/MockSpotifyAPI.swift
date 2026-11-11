import Foundation
import OrbitCore

public struct MockSpotifyAPI: SpotifyAPI {
    public let spotify: MockSpotify

    public init(spotify: MockSpotify) {
        self.spotify = spotify
    }

    public func currentUser() async throws(OrbitError) -> UserProfile {
        await spotify.simulateLatency()
        return MockFixtures.user
    }

    public func playlists(_ page: PageRequest) async throws(OrbitError) -> Page<Playlist> {
        await spotify.simulateLatency()
        return MockSpotify.page(MockFixtures.playlists, page)
    }

    public func playlistItems(playlistID: String, page: PageRequest) async throws(OrbitError) -> Page<Track> {
        await spotify.simulateLatency()
        guard let playlist = MockFixtures.playlists.first(where: { $0.id == playlistID }) else { throw .contentRestricted }
        guard playlist.canReadItems else { throw .playlistItemsUnavailable }
        return MockSpotify.page(MockFixtures.playlistTracks[playlistID] ?? [], page)
    }

    public func savedTracks(_ page: PageRequest) async throws(OrbitError) -> Page<Track> {
        await spotify.simulateLatency()
        return await spotify.savedTracksPage(page)
    }

    public func search(_ query: String, categories: Set<SearchCategory>, page: PageRequest) async throws(OrbitError) -> SearchResults {
        await spotify.simulateLatency()
        let limit = min(page.limit, 10)
        func matches(_ fields: String...) -> Bool {
            fields.contains { $0.localizedStandardContains(query) }
        }
        func window<Item>(_ items: [Item]) -> [Item] {
            Array(items.dropFirst(page.offset).prefix(limit))
        }
        return SearchResults(
            tracks: categories.contains(.track) ? window(MockFixtures.tracks.filter { matches($0.name, $0.artistLine, $0.album) }) : [],
            albums: categories.contains(.album) ? window(MockFixtures.albums.filter { matches($0.name, $0.artists.joined()) }) : [],
            playlists: categories.contains(.playlist) ? window(MockFixtures.playlists.filter { matches($0.name, $0.ownerName) }) : []
        )
    }

    public func playbackState() async throws(OrbitError) -> PlaybackSnapshot? {
        await spotify.simulateLatency()
        return await spotify.snapshot()
    }

    public func devices() async throws(OrbitError) -> [PlaybackDevice] {
        await spotify.simulateLatency()
        return await spotify.availableDevices()
    }

    public func transferPlayback(to deviceID: String, play: Bool) async throws(OrbitError) {
        await spotify.simulateLatency()
        try await spotify.transfer(to: deviceID, play: play)
    }

    public func play(_ target: PlayTarget, deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        try await spotify.play(target)
    }

    public func resume(deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.setPlaying(true)
    }

    public func pause(deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.setPlaying(false)
    }

    public func skipToNext(deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.next()
    }

    public func skipToPrevious(deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.previous()
    }

    public func seek(to position: TimeInterval, deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.seek(to: position)
    }

    public func setVolume(_ percent: Int, deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.setVolume(percent)
    }

    public func setShuffle(_ enabled: Bool, deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.setShuffle(enabled)
    }

    public func setRepeat(_ mode: RepeatMode, deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        await spotify.setRepeat(mode)
    }

    public func queue() async throws(OrbitError) -> PlaybackQueue {
        await spotify.simulateLatency()
        return await spotify.queue()
    }

    public func addToQueue(_ uri: SpotifyURI, deviceID: String?) async throws(OrbitError) {
        try await control(deviceID)
        try await spotify.enqueue(uri)
    }

    public func libraryContains(_ uris: [SpotifyURI]) async throws(OrbitError) -> Set<SpotifyURI> {
        await spotify.simulateLatency()
        return await spotify.libraryContains(uris)
    }

    public func saveToLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        await spotify.simulateLatency()
        await spotify.save(uris)
    }

    public func removeFromLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        await spotify.simulateLatency()
        await spotify.remove(uris)
    }

    private func control(_ deviceID: String?) async throws(OrbitError) {
        await spotify.simulateLatency()
        if let deviceID {
            try await spotify.transfer(to: deviceID, play: false)
        }
        try await spotify.requireControllableDevice()
    }
}
