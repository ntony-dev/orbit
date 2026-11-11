import OrbitCore

// Liked Songs has no playlist ID; it plays as the user's collection context.
public enum LikedSongs {
    public static let playlistID = "orbit.liked-songs"
    public static let name = "Liked Songs"

    public static func contextURI(userID: String) -> SpotifyURI {
        SpotifyURI(rawValue: "spotify:user:\(userID):collection")
    }

    // How a context is started over the Web API. Liked Songs is the one context that may need a different
    // target, so this is the single place to change it.
    static func webTarget(for context: SpotifyURI) -> PlayTarget {
        .context(context)
    }

    public static func playlist(userID: String, ownerName: String?, itemCount: Int?) -> Playlist {
        Playlist(
            id: playlistID,
            uri: contextURI(userID: userID),
            name: name,
            ownerName: ownerName ?? "",
            itemCount: itemCount,
            canReadItems: true
        )
    }

    static func isLikedSongs(_ uri: SpotifyURI) -> Bool {
        uri.kind == .collection
    }
}
