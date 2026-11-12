import Foundation
import OrbitCore

// What the quick picker lists, in display order. Pure, so the section rules are unit tested: pins first, recents
// that are not already pinned, then the whole library under Liked Songs; a filter searches all of it at once.
struct PickerContent: Equatable {
    struct Entry: Identifiable, Equatable {
        // Unique per row: a pinned playlist also appears in the library section below.
        let id: String
        let playlist: Playlist
        let isRecent: Bool
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let title: String?
        var trailing: String?
        let entries: [Entry]
    }

    static let recentLimit = 4

    let sections: [Section]
    let isFiltered: Bool

    var keys: [String] { sections.flatMap { $0.entries.map(\.id) } }

    func entry(for key: String) -> Entry? {
        for section in sections {
            if let entry = section.entries.first(where: { $0.id == key }) { return entry }
        }
        return nil
    }

    init(pinned: [Playlist], recents: [Playlist], liked: Playlist?, library: [Playlist], filter: String) {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        isFiltered = !query.isEmpty
        guard query.isEmpty else {
            let matches = Self.matches(for: query, in: [liked].compactMap { $0 } + library + pinned + recents)
            sections = [Section(
                id: "matches",
                title: nil,
                entries: matches.map { Entry(id: "match:\($0.id)", playlist: $0, isRecent: false) }
            )]
            return
        }
        let pinnedIDs = Set(pinned.map(\.id))
        let freshRecents = recents.filter { !pinnedIDs.contains($0.id) }.prefix(Self.recentLimit)
        let all = [liked].compactMap { $0 } + library
        sections = [
            Section(id: "pinned", title: "Pinned", entries: pinned.map { Entry(id: "pinned:\($0.id)", playlist: $0, isRecent: false) }),
            Section(id: "recent", title: "Recent", entries: freshRecents.map { Entry(id: "recent:\($0.id)", playlist: $0, isRecent: true) }),
            Section(
                id: "library",
                title: "Your Library",
                trailing: library.isEmpty ? nil : "\(library.count)",
                entries: all.map { Entry(id: "library:\($0.id)", playlist: $0, isRecent: false) }
            ),
        ].filter { !$0.entries.isEmpty || $0.id == "library" }
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
