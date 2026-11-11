import Foundation

// Every `deviceID` of nil targets the currently active device.
public protocol SpotifyAPI: Sendable {
    func currentUser() async throws(OrbitError) -> UserProfile
    func playlists(_ page: PageRequest) async throws(OrbitError) -> Page<Playlist>
    // Throws `.playlistItemsUnavailable` for playlists the user neither owns nor collaborates on.
    func playlistItems(playlistID: String, page: PageRequest) async throws(OrbitError) -> Page<Track>
    func savedTracks(_ page: PageRequest) async throws(OrbitError) -> Page<Track>
    // Spotify caps search at 10 results per category.
    func search(_ query: String, categories: Set<SearchCategory>, page: PageRequest) async throws(OrbitError) -> SearchResults

    // Nil when nothing is playing on any device.
    func playbackState() async throws(OrbitError) -> PlaybackSnapshot?
    func devices() async throws(OrbitError) -> [PlaybackDevice]
    func transferPlayback(to deviceID: String, play: Bool) async throws(OrbitError)
    func play(_ target: PlayTarget, deviceID: String?) async throws(OrbitError)
    func resume(deviceID: String?) async throws(OrbitError)
    func pause(deviceID: String?) async throws(OrbitError)
    func skipToNext(deviceID: String?) async throws(OrbitError)
    func skipToPrevious(deviceID: String?) async throws(OrbitError)
    func seek(to position: TimeInterval, deviceID: String?) async throws(OrbitError)
    func setVolume(_ percent: Int, deviceID: String?) async throws(OrbitError)
    func setShuffle(_ enabled: Bool, deviceID: String?) async throws(OrbitError)
    func setRepeat(_ mode: RepeatMode, deviceID: String?) async throws(OrbitError)

    func queue() async throws(OrbitError) -> PlaybackQueue
    func addToQueue(_ uri: SpotifyURI, deviceID: String?) async throws(OrbitError)

    // Returns the subset of `uris` that is saved in the user's library.
    func libraryContains(_ uris: [SpotifyURI]) async throws(OrbitError) -> Set<SpotifyURI>
    func saveToLibrary(_ uris: [SpotifyURI]) async throws(OrbitError)
    func removeFromLibrary(_ uris: [SpotifyURI]) async throws(OrbitError)
}
