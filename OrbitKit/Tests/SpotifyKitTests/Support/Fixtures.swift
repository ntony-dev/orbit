// Response bodies shaped like the examples on developer.spotify.com's reference pages as of November 2026,
// including the post-migration renames (`items`/`item`) and the nulls that real libraries contain.
enum Fixtures {
    static let me = """
    {
      "account_id": "acc-9f2",
      "display_name": "Tony",
      "external_urls": {"spotify": "https://open.spotify.com/user/tony"},
      "href": "https://api.spotify.com/v1/users/tony",
      "id": "tony",
      "images": [
        {"url": "https://i.scdn.co/image/avatar-640", "height": 640, "width": 640},
        {"url": "https://i.scdn.co/image/avatar-64", "height": 64, "width": 64}
      ],
      "type": "user",
      "uri": "spotify:user:tony"
    }
    """

    static let track = """
    {
      "album": {
        "album_type": "album", "total_tracks": 10, "id": "alb1", "name": "Blue Hours",
        "images": [
          {"url": "https://i.scdn.co/image/alb1-640", "height": 640, "width": 640},
          {"url": "https://i.scdn.co/image/alb1-300", "height": 300, "width": 300},
          {"url": "https://i.scdn.co/image/alb1-64", "height": 64, "width": 64}
        ],
        "release_date": "2024-01-01", "release_date_precision": "day", "type": "album", "uri": "spotify:album:alb1",
        "artists": [{"id": "art1", "name": "Nova", "type": "artist", "uri": "spotify:artist:art1"}]
      },
      "artists": [
        {"id": "art1", "name": "Nova", "type": "artist", "uri": "spotify:artist:art1"},
        {"id": "art2", "name": "Echo", "type": "artist", "uri": "spotify:artist:art2"}
      ],
      "disc_number": 1, "duration_ms": 215000, "explicit": true,
      "external_ids": {"isrc": "USX1"}, "external_urls": {"spotify": "https://open.spotify.com/track/trk1"},
      "href": "https://api.spotify.com/v1/tracks/trk1", "id": "trk1", "is_playable": true,
      "name": "Night Drive", "track_number": 3, "type": "track", "uri": "spotify:track:trk1", "is_local": false
    }
    """

    static let episode = """
    {
      "audio_preview_url": null, "description": "Talk", "duration_ms": 1800000, "explicit": false,
      "id": "ep1", "images": [{"url": "https://i.scdn.co/image/ep1", "height": 300, "width": 300}],
      "is_externally_hosted": false, "is_playable": true, "languages": ["en"], "name": "Episode One",
      "release_date": "2026-01-01", "release_date_precision": "day", "type": "episode", "uri": "spotify:episode:ep1",
      "show": {"id": "show1", "name": "The Show", "images": [], "type": "show", "uri": "spotify:show:show1", "total_episodes": 10}
    }
    """

    static let restrictedTrack = """
    {
      "album": {"id": "alb2", "name": "Gone", "images": [], "artists": []},
      "artists": [{"name": "Ghost"}], "duration_ms": 1000, "explicit": false, "id": "trk2",
      "name": "Unavailable", "type": "track", "uri": "spotify:track:trk2", "is_local": false,
      "restrictions": {"reason": "market"}
    }
    """

    static let playlists = """
    {
      "href": "https://api.spotify.com/v1/me/playlists?offset=0&limit=3", "limit": 3,
      "next": "https://api.spotify.com/v1/me/playlists?offset=3&limit=3", "offset": 0, "previous": null, "total": 7,
      "items": [
        {
          "collaborative": false, "description": "Late &amp; slow <a href=\\"spotify:playlist:x\\">mix</a>",
          "external_urls": {"spotify": "https://open.spotify.com/playlist/pl-own"}, "href": "https://api.spotify.com/v1/playlists/pl-own",
          "id": "pl-own", "images": [{"url": "https://mosaic.scdn.co/640/own", "height": 640, "width": 640}],
          "name": "Night Drive", "owner": {"display_name": "Tony", "id": "tony", "type": "user", "uri": "spotify:user:tony"},
          "public": false, "snapshot_id": "snap", "items": {"href": "https://api.spotify.com/v1/playlists/pl-own/items", "total": 42},
          "tracks": {"href": "https://api.spotify.com/v1/playlists/pl-own/tracks", "total": 42},
          "type": "playlist", "uri": "spotify:playlist:pl-own"
        },
        {
          "collaborative": true, "description": null, "id": "pl-collab", "images": null,
          "name": "Road Trip", "owner": {"display_name": null, "id": "friend", "type": "user"},
          "public": null, "snapshot_id": "snap", "items": {"href": "x", "total": 12}, "type": "playlist", "uri": "spotify:playlist:pl-collab"
        },
        {
          "collaborative": false, "description": "", "id": "pl-followed",
          "images": [{"url": "https://i.scdn.co/image/followed", "height": null, "width": null}],
          "name": "Today's Hits", "owner": {"display_name": "Spotify", "id": "spotify", "type": "user"},
          "public": true, "snapshot_id": "snap", "type": "playlist", "uri": "spotify:playlist:pl-followed"
        }
      ]
    }
    """

    static let playlistItems = """
    {
      "href": "https://api.spotify.com/v1/playlists/pl-own/items?offset=0&limit=5", "limit": 5,
      "next": "https://api.spotify.com/v1/playlists/pl-own/items?offset=5&limit=5", "offset": 0, "previous": null, "total": 9,
      "items": [
        {"added_at": "2026-03-01T10:00:00Z", "added_by": {"id": "tony", "type": "user"}, "is_local": false, "item": \(track), "track": \(track)},
        {"added_at": null, "added_by": null, "is_local": false, "item": null, "track": null},
        {"added_at": "2026-03-02T10:00:00Z", "is_local": true, "item": {"id": null, "name": "My Demo.mp3", "type": "track", "uri": "spotify:local:Me::My+Demo:180", "is_local": true, "duration_ms": 180000}},
        {"added_at": "2026-03-03T10:00:00Z", "is_local": false, "item": \(episode)},
        {"added_at": "2026-03-04T10:00:00Z", "is_local": false, "item": \(restrictedTrack)}
      ]
    }
    """

    static let savedTracks = """
    {
      "href": "https://api.spotify.com/v1/me/tracks?offset=0&limit=2", "limit": 2, "next": null, "offset": 0, "previous": null, "total": 2,
      "items": [
        {"added_at": "2026-05-01T00:00:00Z", "track": \(track)},
        {"added_at": "2026-05-02T00:00:00Z", "track": \(restrictedTrack)}
      ]
    }
    """

    static let search = """
    {
      "tracks": {"href": "x", "limit": 5, "next": null, "offset": 0, "previous": null, "total": 1, "items": [\(track)]},
      "albums": {"href": "x", "limit": 5, "next": null, "offset": 0, "previous": null, "total": 1, "items": [
        {"album_type": "album", "total_tracks": 10, "id": "alb1", "name": "Blue Hours", "type": "album", "uri": "spotify:album:alb1",
         "images": [{"url": "https://i.scdn.co/image/alb1-300", "height": 300, "width": 300}],
         "artists": [{"name": "Nova"}], "release_date": "2024", "release_date_precision": "year"}
      ]},
      "playlists": {"href": "x", "limit": 5, "next": "y", "offset": 0, "previous": null, "total": 3, "items": [
        null,
        {"collaborative": false, "description": "Fresh", "id": "pl-search", "images": [], "name": "Nova Radio",
         "owner": {"display_name": "Spotify", "id": "spotify"}, "items": {"href": "x", "total": 50}, "type": "playlist", "uri": "spotify:playlist:pl-search"}
      ]}
    }
    """

    static let playbackState = """
    {
      "device": {"id": "dev-mac", "is_active": true, "is_private_session": false, "is_restricted": false,
                 "name": "Tony's MacBook", "type": "Computer", "volume_percent": 64, "supports_volume": true},
      "repeat_state": "context", "shuffle_state": true, "smart_shuffle": false,
      "context": {"type": "playlist", "href": "https://api.spotify.com/v1/playlists/pl-own",
                  "external_urls": {"spotify": "https://open.spotify.com/playlist/pl-own"}, "uri": "spotify:playlist:pl-own"},
      "timestamp": 1800000000000, "progress_ms": 61500, "is_playing": true,
      "item": \(track),
      "currently_playing_type": "track",
      "actions": {"disallows": {"resuming": true, "skipping_prev": true, "toggling_repeat_track": false}}
    }
    """

    static let devices = """
    {
      "devices": [
        {"id": "dev-mac", "is_active": true, "is_private_session": false, "is_restricted": false, "name": "Tony's MacBook", "type": "Computer", "volume_percent": 64, "supports_volume": true},
        {"id": "dev-tv", "is_active": false, "is_private_session": false, "is_restricted": true, "name": "Living Room TV", "type": "TV", "volume_percent": null, "supports_volume": false},
        {"id": null, "is_active": false, "is_private_session": false, "is_restricted": true, "name": "Hidden", "type": "Speaker", "volume_percent": null, "supports_volume": false},
        {"id": "dev-cast", "is_active": false, "is_private_session": false, "is_restricted": false, "name": "Kitchen", "type": "CastAudio", "volume_percent": 30, "supports_volume": true}
      ]
    }
    """

    static let queue = """
    {"currently_playing": \(track), "queue": [\(episode), null, \(restrictedTrack)]}
    """

    // Player 404s as Spotify sends them: the no-device body is the one community reports show with a reason; the
    // stale device_id and missing-context bodies carry no reason, and the play reference documents none of them.
    static let noActiveDevice404 = #"{"error":{"status":404,"message":"Player command failed: No active device found","reason":"NO_ACTIVE_DEVICE"}}"#
    static let deviceNotFound404 = #"{"error":{"status":404,"message":"Device not found"}}"#
    static let contextNotFound404 = #"{"error":{"status":404,"message":"Not found."}}"#

    static func error(status: Int, message: String, reason: String? = nil) -> String {
        let reasonField = reason.map { #","reason":"\#($0)""# } ?? ""
        return #"{"error":{"status":\#(status),"message":"\#(message)"\#(reasonField)}}"#
    }
}
