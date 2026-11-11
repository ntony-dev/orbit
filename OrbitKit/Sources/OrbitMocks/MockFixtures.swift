import Foundation
import OrbitCore

// Invented artists and titles, shaped like real Spotify data, for tests, previews and `--demo`.
public enum MockFixtures {
    public static let user = UserProfile(id: "orbit-demo", displayName: "Demo Listener")

    private struct AlbumSeed {
        let id: String
        let name: String
        let artist: String
        let palette: MockArtwork.Palette
        let tracks: [(String, Int)]
    }

    private static let albumSeeds: [AlbumSeed] = [
        AlbumSeed(id: "al-neon-harbor", name: "Neon Harbor", artist: "Lumen Drift", palette: .init(0x523752, 0xAD7B8A),
                  tracks: [("Afterglow Avenue", 224), ("Harbor Lights", 251), ("Velvet Static", 198), ("Glass City", 263)]),
        AlbumSeed(id: "al-quiet-signal", name: "Quiet Signal", artist: "Northpaw", palette: .init(0x22384F, 0x6F9CC4),
                  tracks: [("Low Orbit", 312), ("Signal Fade", 287), ("Paper Satellites", 241)]),
        AlbumSeed(id: "al-iron-tempo", name: "Iron Tempo", artist: "Kilo Vance", palette: .init(0x4E634E, 0xB7A86E),
                  tracks: [("Rep Count", 176), ("Concrete Sprint", 189), ("Heavy Air", 203), ("Last Set", 214)]),
        AlbumSeed(id: "al-linen", name: "Linen Mornings", artist: "Ada Farrow", palette: .init(0xC9A27E, 0xEFD9C1),
                  tracks: [("Kettle Song", 205), ("Open Windows", 233), ("Slow Toast", 187)]),
        AlbumSeed(id: "al-mile-markers", name: "Mile Markers", artist: "The Long Weekends", palette: .init(0x8C4A2F, 0xE0A458),
                  tracks: [("Exit 41", 219), ("Gas Station Coffee", 196), ("Desert Radio", 248), ("Sunroof", 207)]),
        AlbumSeed(id: "al-rain-tapes", name: "Rain Tapes", artist: "softcassette", palette: .init(0x3D4A5C, 0x9AA9B8),
                  tracks: [("drizzle.wav", 142), ("window seat", 158), ("tea gone cold", 133), ("umbrella loop", 149)]),
        AlbumSeed(id: "al-chart-glow", name: "Chart Glow", artist: "Mira Sol", palette: .init(0xC2185B, 0xFF8A65),
                  tracks: [("Headline", 183), ("Gold Rush Heart", 201), ("Phone Light", 177)]),
        AlbumSeed(id: "al-paper-kites", name: "Paper Kites Club", artist: "Juniper Lane", palette: .init(0x2E6B5E, 0x9AD0B5),
                  tracks: [("Bicycle Bell", 196), ("Small Town Static", 222), ("Overgrown", 239)]),
        AlbumSeed(id: "al-blue-room", name: "The Blue Room Sessions", artist: "Oskar Wren Trio", palette: .init(0x1B2340, 0x4B5FA8),
                  tracks: [("Smoke Ring Waltz", 334), ("Midnight Ledger", 298), ("Brushes", 276)]),
        AlbumSeed(id: "al-mixtape-2009", name: "Mixtape 2009", artist: "Bright Mondays", palette: .init(0x7B2CBF, 0xF72585),
                  tracks: [("Text Me Back", 204), ("Mall Parking Lot", 215), ("Flip Phone Summer", 198)]),
        AlbumSeed(id: "al-chrome-horizon", name: "Chrome Horizon", artist: "VHS Arcade", palette: .init(0x3A0CA3, 0xFF6D00),
                  tracks: [("Laser Grid", 268), ("Palm Silhouette", 252), ("Night Drive 1986", 289)]),
        AlbumSeed(id: "al-compile", name: "Compile Time", artist: "Byte Garden", palette: .init(0x0F3D3E, 0x3FA796),
                  tracks: [("Green Build", 231), ("Merge Window", 244), ("Hot Reload", 219)]),
    ]

    public static let albums: [Album] = albumSeeds.map {
        Album(id: $0.id, name: $0.name, artists: [$0.artist], artworkURL: MockArtwork.url(for: $0.id))
    }

    public static let tracks: [Track] = albumSeeds.flatMap { album in
        album.tracks.enumerated().map { index, seed in
            Track(
                id: "\(album.id)-\(index + 1)",
                name: seed.0,
                artists: [album.artist],
                album: album.name,
                artworkURL: MockArtwork.url(for: album.id),
                duration: TimeInterval(seed.1),
                isExplicit: album.id == "al-iron-tempo" && index == 1
            )
        }
    }

    private struct PlaylistSeed {
        let id: String
        let name: String
        let summary: String
        let owner: String
        let canReadItems: Bool
        let palette: MockArtwork.Palette
        let albumIDs: [String]
    }

    private static let playlistSeeds: [PlaylistSeed] = [
        PlaylistSeed(id: "pl-night-drive", name: "Night Drive", summary: "Neon, chrome and empty highways.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x523752, 0xAD7B8A), albumIDs: ["al-neon-harbor", "al-chrome-horizon", "al-quiet-signal"]),
        PlaylistSeed(id: "pl-deep-focus", name: "Deep Focus Flow", summary: "Long tracks, no lyrics, no distractions.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x22384F, 0x6F9CC4), albumIDs: ["al-quiet-signal", "al-compile", "al-rain-tapes"]),
        PlaylistSeed(id: "pl-gym", name: "Gym Rotation", summary: "Tempo up.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x4E634E, 0xB7A86E), albumIDs: ["al-iron-tempo", "al-chart-glow"]),
        PlaylistSeed(id: "pl-sunday", name: "Sunday Slow Morning", summary: "Coffee first.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0xC9A27E, 0xEFD9C1), albumIDs: ["al-linen", "al-paper-kites"]),
        PlaylistSeed(id: "pl-road-trip", name: "Road Trip '26", summary: "Shared with the car.", owner: "Maya",
                     canReadItems: true, palette: .init(0x8C4A2F, 0xE0A458), albumIDs: ["al-mile-markers", "al-mixtape-2009", "al-paper-kites"]),
        PlaylistSeed(id: "pl-lofi-rain", name: "Lo-fi Rainy Window", summary: "Beats to stare outside to.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x3D4A5C, 0x9AA9B8), albumIDs: ["al-rain-tapes"]),
        PlaylistSeed(id: "pl-top-hits", name: "Today's Top Hits", summary: "The hottest tracks right now.", owner: "Spotify",
                     canReadItems: false, palette: .init(0xC2185B, 0xFF8A65), albumIDs: ["al-chart-glow", "al-iron-tempo", "al-mixtape-2009"]),
        PlaylistSeed(id: "pl-indie-pulse", name: "Indie Pulse", summary: "Guitars with feelings.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x2E6B5E, 0x9AD0B5), albumIDs: ["al-paper-kites", "al-mile-markers"]),
        PlaylistSeed(id: "pl-late-jazz", name: "Late Night Jazz", summary: "Brushes and low light.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x1B2340, 0x4B5FA8), albumIDs: ["al-blue-room"]),
        PlaylistSeed(id: "pl-throwback", name: "Throwback Anthems", summary: "You know every word.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x7B2CBF, 0xF72585), albumIDs: ["al-mixtape-2009", "al-chart-glow"]),
        PlaylistSeed(id: "pl-synthwave", name: "Synthwave Sunset", summary: "Retro futures.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x3A0CA3, 0xFF6D00), albumIDs: ["al-chrome-horizon", "al-neon-harbor"]),
        PlaylistSeed(id: "pl-coding", name: "Coding Marathon", summary: "Ship it.", owner: user.displayName!,
                     canReadItems: true, palette: .init(0x0F3D3E, 0x3FA796), albumIDs: ["al-compile", "al-quiet-signal", "al-rain-tapes"]),
    ]

    // Every playlist's tracks, including those the API hides, because context playback still works for them.
    public static let playlistTracks: [String: [Track]] = Dictionary(uniqueKeysWithValues: playlistSeeds.map { seed in
        (seed.id, seed.albumIDs.flatMap { albumID in tracks.filter { $0.id.hasPrefix(albumID + "-") } })
    })

    public static let playlists: [Playlist] = playlistSeeds.map { seed in
        Playlist(
            id: seed.id,
            name: seed.name,
            summary: seed.summary,
            ownerName: seed.owner,
            artworkURL: MockArtwork.url(for: seed.id),
            itemCount: seed.canReadItems ? playlistTracks[seed.id]?.count : nil,
            canReadItems: seed.canReadItems
        )
    }

    public static let devices: [PlaybackDevice] = [
        PlaybackDevice(id: "dev-mac", name: "This Mac", kind: .computer, isActive: true, volumePercent: 64),
        PlaybackDevice(id: "dev-phone", name: "Pocket Phone", kind: .smartphone, supportsVolume: false),
        PlaybackDevice(id: "dev-kitchen", name: "Kitchen Speaker", kind: .speaker, volumePercent: 40),
        PlaybackDevice(id: "dev-tv", name: "Living Room TV", kind: .television, isRestricted: true, supportsVolume: false),
    ]

    public static let savedTrackIDs: [String] = ["al-neon-harbor-1", "al-quiet-signal-1", "al-linen-2", "al-blue-room-1", "al-compile-1"]

    public static let queuedTrackIDs: [String] = ["al-paper-kites-1", "al-mile-markers-3"]

    public static func track(id: String) -> Track? {
        tracks.first { $0.id == id }
    }

    static var artwork: [String: MockArtwork.Palette] {
        var artwork: [String: MockArtwork.Palette] = [:]
        for seed in albumSeeds { artwork[seed.id] = seed.palette }
        for seed in playlistSeeds { artwork[seed.id] = seed.palette }
        return artwork
    }
}
