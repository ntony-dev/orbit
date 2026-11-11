import Foundation
import OrbitCore

// Seam for the Web API client. Not implemented yet: every call fails with a typed error.
public actor SpotifyWebClient: SpotifyAPI {
    private static let unavailable = OrbitError.notImplemented(feature: "The Spotify Web API")

    private let authorizer: SpotifyAuthorizer

    public init(authorizer: SpotifyAuthorizer) {
        self.authorizer = authorizer
    }

    public func currentUser() async throws(OrbitError) -> UserProfile {
        throw Self.unavailable
    }

    public func playlists(_ page: PageRequest) async throws(OrbitError) -> Page<Playlist> {
        throw Self.unavailable
    }

    public func playlistItems(playlistID: String, page: PageRequest) async throws(OrbitError) -> Page<Track> {
        throw Self.unavailable
    }

    public func savedTracks(_ page: PageRequest) async throws(OrbitError) -> Page<Track> {
        throw Self.unavailable
    }

    public func search(_ query: String, categories: Set<SearchCategory>, page: PageRequest) async throws(OrbitError) -> SearchResults {
        throw Self.unavailable
    }

    public func playbackState() async throws(OrbitError) -> PlaybackSnapshot? {
        throw Self.unavailable
    }

    public func devices() async throws(OrbitError) -> [PlaybackDevice] {
        throw Self.unavailable
    }

    public func transferPlayback(to deviceID: String, play: Bool) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func play(_ target: PlayTarget, deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func resume(deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func pause(deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func skipToNext(deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func skipToPrevious(deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func seek(to position: TimeInterval, deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func setVolume(_ percent: Int, deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func setShuffle(_ enabled: Bool, deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func setRepeat(_ mode: RepeatMode, deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func queue() async throws(OrbitError) -> PlaybackQueue {
        throw Self.unavailable
    }

    public func addToQueue(_ uri: SpotifyURI, deviceID: String?) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func libraryContains(_ uris: [SpotifyURI]) async throws(OrbitError) -> Set<SpotifyURI> {
        throw Self.unavailable
    }

    public func saveToLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        throw Self.unavailable
    }

    public func removeFromLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        throw Self.unavailable
    }
}
