public enum SearchCategory: String, CaseIterable, Hashable, Codable, Sendable {
    case track, album, playlist
}

public struct SearchResults: Hashable, Codable, Sendable {
    public var tracks: [Track]
    public var albums: [Album]
    public var playlists: [Playlist]

    public init(tracks: [Track] = [], albums: [Album] = [], playlists: [Playlist] = []) {
        self.tracks = tracks
        self.albums = albums
        self.playlists = playlists
    }

    public var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && playlists.isEmpty }
}
