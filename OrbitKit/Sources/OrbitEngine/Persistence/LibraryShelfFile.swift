import Foundation
import OrbitCore

// Pinned and recent playlists, stored as full playlist values so they still show after a restart even when the
// playlist has since been deleted or unfollowed.
struct LibraryShelf: Hashable, Codable, Sendable {
    var pinned: [Playlist]
    var recents: [Playlist]

    init(pinned: [Playlist] = [], recents: [Playlist] = []) {
        self.pinned = pinned
        self.recents = recents
    }
}

// A small JSON file written atomically off the main thread.
public actor LibraryShelfFile {
    nonisolated let url: URL
    private var savedRevision = -1

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Orbit", directoryHint: .isDirectory)
            .appending(path: "Library.json", directoryHint: .notDirectory)
    }

    func load() -> LibraryShelf? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LibraryShelf.self, from: data)
    }

    // Saves are fired from the main actor without waiting; the revision keeps an older one from landing last.
    func save(_ shelf: LibraryShelf, revision: Int) {
        guard revision > savedRevision else { return }
        savedRevision = revision
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(shelf).write(to: url, options: .atomic)
        } catch {
            // Pins stay in memory for this session; the next change tries to write again.
            savedRevision = revision - 1
        }
    }
}
