import Foundation
import OrbitCore

// What the library lists, in display order. Pure, so the section and keyboard rules are unit tested. Without a
// query: pins, then up to three recents that are not pinned, then Liked Songs and every playlist not already
// shown above. With one: the user's own playlists that match, then Spotify's results for it.
struct LibraryContent: Equatable {
    enum Item: Equatable {
        case playlist(Playlist, isRecent: Bool)
        case track(Track)
        case album(Album)

        // A playlist row opens into its tracks; songs and albums only play.
        var opensTracks: Playlist? {
            if case .playlist(let playlist, _) = self { return playlist }
            return nil
        }
    }

    struct Entry: Identifiable, Equatable {
        // The row's key for selection and scrolling, unique across both parts of the list.
        let id: String
        let item: Item
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    static let recentLimit = 3

    let query: String
    // The user's playlists: Pinned, Recent and Your Library, or the matches for the query.
    let sections: [Section]
    // Spotify's results for the query, grouped by kind; empty without a query or before results arrive.
    let spotify: [Section]

    var isFiltered: Bool { !query.isEmpty }

    var keys: [String] { (sections + spotify).flatMap { $0.entries.map(\.id) } }

    func entry(for key: String) -> Entry? {
        for section in sections + spotify {
            if let entry = section.entries.first(where: { $0.id == key }) { return entry }
        }
        return nil
    }

    init(pinned: [Playlist], recents: [Playlist], liked: Playlist?, library: [Playlist], query: String, results: SearchResults? = nil) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query
        let all = [liked].compactMap { $0 } + library
        guard query.isEmpty else {
            let matches = Self.matches(for: query, in: all + pinned + recents)
            let matchIDs = Set(matches.map(\.id))
            let recentIDs = Set(recents.map(\.id))
            sections = [Section(
                id: "matches",
                title: "Your Library",
                entries: matches.map { Entry(id: "match:\($0.id)", item: .playlist($0, isRecent: recentIDs.contains($0.id))) }
            )].filter { !$0.entries.isEmpty }
            let results = results ?? SearchResults()
            spotify = [
                Section(id: "songs", title: "Songs", entries: results.tracks.enumerated().map { index, track in
                    Entry(id: "track:\(index)", item: .track(track))
                }),
                Section(id: "albums", title: "Albums", entries: results.albums.map { Entry(id: "album:\($0.id)", item: .album($0)) }),
                // A playlist of the user's that Spotify also found is already listed among the matches above.
                Section(id: "playlists", title: "Playlists", entries: results.playlists.filter { !matchIDs.contains($0.id) }.map {
                    Entry(id: "spotify:\($0.id)", item: .playlist($0, isRecent: false))
                }),
            ].filter { !$0.entries.isEmpty }
            return
        }
        let pinnedIDs = Set(pinned.map(\.id))
        let freshRecents = Array(recents.filter { !pinnedIDs.contains($0.id) }.prefix(Self.recentLimit))
        let shown = pinnedIDs.union(freshRecents.map(\.id))
        sections = [
            Section(id: "pinned", title: "Pinned", entries: pinned.map { Entry(id: "pinned:\($0.id)", item: .playlist($0, isRecent: false)) }),
            Section(id: "recent", title: "Recent", entries: freshRecents.map { Entry(id: "recent:\($0.id)", item: .playlist($0, isRecent: true)) }),
            Section(id: "library", title: "Your Library", entries: all.filter { !shown.contains($0.id) }.map {
                Entry(id: "library:\($0.id)", item: .playlist($0, isRecent: false))
            }),
        ].filter { !$0.entries.isEmpty }
        spotify = []
    }

    // Names that start with the query, or have a word that does, rank above names that merely contain it, so
    // "gym" puts Gym Rotation first. Duplicates (a pin that is also in the library) appear once.
    static func matches(for query: String, in playlists: [Playlist]) -> [Playlist] {
        var seen = Set<Playlist.ID>()
        let unique = playlists.filter { seen.insert($0.id).inserted }
        let found = unique.filter { $0.name.localizedStandardContains(query) }
        let leading = found.filter { name in
            name.name.localizedStandardRange(of: query).map { range in
                range.lowerBound == name.name.startIndex || !name.name[name.name.index(before: range.lowerBound)].isLetter
            } ?? false
        }
        let leadingIDs = Set(leading.map(\.id))
        return leading + found.filter { !leadingIDs.contains($0.id) }
    }
}
