import Foundation

public struct Track: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var uri: SpotifyURI
    public var name: String
    public var artists: [String]
    public var album: String
    public var artworkURL: URL?
    public var duration: TimeInterval
    public var isExplicit: Bool
    // False when Spotify reports the track as unplayable in the user's market or account.
    public var isPlayable: Bool

    public init(
        id: String,
        uri: SpotifyURI? = nil,
        name: String,
        artists: [String],
        album: String,
        artworkURL: URL? = nil,
        duration: TimeInterval,
        isExplicit: Bool = false,
        isPlayable: Bool = true
    ) {
        self.id = id
        self.uri = uri ?? SpotifyURI(.track, id: id)
        self.name = name
        self.artists = artists
        self.album = album
        self.artworkURL = artworkURL
        self.duration = duration
        self.isExplicit = isExplicit
        self.isPlayable = isPlayable
    }

    public var artistLine: String { artists.joined(separator: ", ") }
}

public struct Album: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var uri: SpotifyURI
    public var name: String
    public var artists: [String]
    public var artworkURL: URL?

    public init(id: String, uri: SpotifyURI? = nil, name: String, artists: [String], artworkURL: URL? = nil) {
        self.id = id
        self.uri = uri ?? SpotifyURI(.album, id: id)
        self.name = name
        self.artists = artists
        self.artworkURL = artworkURL
    }
}

public struct Playlist: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var uri: SpotifyURI
    public var name: String
    public var summary: String?
    public var ownerName: String
    public var artworkURL: URL?
    // Nil when Spotify omits the count, which it does for playlists whose items are hidden.
    public var itemCount: Int?
    // Spotify returns items only for playlists the user owns or collaborates on; others still play as a context.
    public var canReadItems: Bool

    public init(
        id: String,
        uri: SpotifyURI? = nil,
        name: String,
        summary: String? = nil,
        ownerName: String,
        artworkURL: URL? = nil,
        itemCount: Int? = nil,
        canReadItems: Bool
    ) {
        self.id = id
        self.uri = uri ?? SpotifyURI(.playlist, id: id)
        self.name = name
        self.summary = summary
        self.ownerName = ownerName
        self.artworkURL = artworkURL
        self.itemCount = itemCount
        self.canReadItems = canReadItems
    }
}

public struct UserProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var displayName: String?
    public var avatarURL: URL?

    public init(id: String, displayName: String? = nil, avatarURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    public var uri: SpotifyURI { SpotifyURI(.user, id: id) }
}
