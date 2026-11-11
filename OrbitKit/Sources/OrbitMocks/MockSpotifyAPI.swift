import Foundation
import OrbitCore

public struct MockSpotifyAPI: SpotifyAPI {
    public let spotify: MockSpotify

    public init(spotify: MockSpotify) {
        self.spotify = spotify
    }

    public func currentUser() async throws(OrbitError) -> UserProfile {
        try await spotify.webRequest("currentUser")
        return MockFixtures.user
    }

    public func playlists(_ page: PageRequest) async throws(OrbitError) -> Page<Playlist> {
        try await spotify.webRequest("playlists")
        return MockSpotify.page(await spotify.libraryPlaylists(), page)
    }

    public func playlistItems(playlistID: String, page: PageRequest) async throws(OrbitError) -> Page<Track> {
        try await spotify.webRequest("playlistItems")
        guard let playlist = await spotify.libraryPlaylists().first(where: { $0.id == playlistID }) else { throw .contentRestricted }
        guard playlist.canReadItems else { throw .playlistItemsUnavailable }
        return MockSpotify.page(MockFixtures.playlistTracks[playlistID] ?? [], page)
    }

    public func savedTracks(_ page: PageRequest) async throws(OrbitError) -> Page<Track> {
        try await spotify.webRequest("savedTracks")
        return await spotify.savedTracksPage(page)
    }

    public func search(_ query: String, categories: Set<SearchCategory>, page: PageRequest) async throws(OrbitError) -> SearchResults {
        try await spotify.webRequest("search")
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
        try await spotify.webRequest("playbackState")
        return await spotify.snapshot()
    }

    public func devices() async throws(OrbitError) -> [PlaybackDevice] {
        try await spotify.webRequest("devices")
        return await spotify.availableDevices()
    }

    public func transferPlayback(to deviceID: String, play: Bool) async throws(OrbitError) {
        try await spotify.webRequest("transferPlayback", isCommand: true)
        try await spotify.transfer(to: deviceID, play: play)
    }

    public func play(_ target: PlayTarget, deviceID: String?) async throws(OrbitError) {
        try await control("play", deviceID)
        if case .context(let uri, let offset) = target, uri.kind == .collection, await spotify.rejectsLikedSongsContext {
            let uris = await spotify.savedTrackURIs(limit: 100)
            let trackOffset = offset.flatMap { if case .track(let track) = $0, uris.contains(track) { $0 } else { nil } }
            try await spotify.play(.tracks(uris, offset: trackOffset))
            return
        }
        try await spotify.play(target)
    }

    public func resume(deviceID: String?) async throws(OrbitError) {
        try await control("resume", deviceID)
        await spotify.setPlaying(true)
    }

    public func pause(deviceID: String?) async throws(OrbitError) {
        try await control("pause", deviceID)
        await spotify.setPlaying(false)
    }

    public func skipToNext(deviceID: String?) async throws(OrbitError) {
        try await control("skipToNext", deviceID)
        await spotify.next()
    }

    public func skipToPrevious(deviceID: String?) async throws(OrbitError) {
        try await control("skipToPrevious", deviceID)
        await spotify.previous()
    }

    public func seek(to position: TimeInterval, deviceID: String?) async throws(OrbitError) {
        try await control("seek", deviceID)
        await spotify.seek(to: position)
    }

    public func setVolume(_ percent: Int, deviceID: String?) async throws(OrbitError) {
        try await control("setVolume", deviceID)
        try await spotify.requireVolumeControl()
        await spotify.setVolume(percent)
    }

    public func setShuffle(_ enabled: Bool, deviceID: String?) async throws(OrbitError) {
        try await control("setShuffle", deviceID)
        await spotify.setShuffle(enabled)
    }

    public func setRepeat(_ mode: RepeatMode, deviceID: String?) async throws(OrbitError) {
        try await control("setRepeat", deviceID)
        await spotify.setRepeat(mode)
    }

    public func queue() async throws(OrbitError) -> PlaybackQueue {
        try await spotify.webRequest("queue")
        return await spotify.queue()
    }

    public func addToQueue(_ uri: SpotifyURI, deviceID: String?) async throws(OrbitError) {
        try await control("addToQueue", deviceID)
        try await spotify.enqueue(uri)
    }

    public func libraryContains(_ uris: [SpotifyURI]) async throws(OrbitError) -> Set<SpotifyURI> {
        try await spotify.webRequest("libraryContains")
        return await spotify.libraryContains(uris)
    }

    public func saveToLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        try await spotify.webRequest("saveToLibrary", isCommand: true)
        await spotify.save(uris)
    }

    public func removeFromLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        try await spotify.webRequest("removeFromLibrary", isCommand: true)
        await spotify.remove(uris)
    }

    private func control(_ name: String, _ deviceID: String?) async throws(OrbitError) {
        try await spotify.webRequest(name, isCommand: true)
        if let deviceID {
            try await spotify.transfer(to: deviceID, play: false)
        }
        try await spotify.requireControllableDevice()
    }
}
