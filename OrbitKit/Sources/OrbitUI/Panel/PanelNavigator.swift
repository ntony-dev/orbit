import CoreGraphics
import Observation
import OrbitCore

enum PanelSection: Int, CaseIterable, Hashable {
    case player, picker, library
}

enum LibraryTab: Hashable, CaseIterable {
    case playlists, liked, queue, search
}

// A layer pushed over a section: playlist contents from the library, or the device list from the player.
enum PanelDetail: Hashable {
    case playlist(Playlist)
    case devices
}

// Where the expanded surface is. Owned by the UI alone; the shell only expresses an initial destination through
// PanelState.requestedDestination.
@MainActor
@Observable
final class PanelNavigator {
    private(set) var section: PanelSection = .player
    private(set) var detail: PanelDetail?
    var libraryTab: LibraryTab = .playlists
    // Kept here rather than in the search screen so leaving and returning keeps the query and its results.
    var searchQuery = ""
    // Which way the last move went, so the incoming screen slides in from the side the user is heading toward.
    private(set) var isForward = true
    // Bumped when search should take focus as soon as it appears (a "focus search" request from outside).
    private(set) var searchFocusRequest = 0

    var depth: Int {
        (section == .player ? 0 : 1) + (detail == nil ? 0 : 1)
    }

    func show(_ newSection: PanelSection) {
        guard newSection != section || detail != nil else { return }
        isForward = newSection.rawValue >= section.rawValue
        section = newSection
        detail = nil
    }

    func push(_ newDetail: PanelDetail) {
        isForward = true
        detail = newDetail
    }

    func showLibrary(_ tab: LibraryTab) {
        libraryTab = tab
        show(.library)
    }

    // Steps back one layer and reports whether there was one to leave.
    @discardableResult
    func back() -> Bool {
        isForward = false
        if detail != nil {
            detail = nil
            return true
        }
        if section != .player {
            section = .player
            return true
        }
        return false
    }

    func reset(to destination: PanelDestination) {
        isForward = true
        detail = nil
        switch destination {
        case .player:
            section = .player
        case .playlistPicker:
            section = .picker
        case .search:
            libraryTab = .search
            section = .library
            searchFocusRequest += 1
        }
    }

    var screenSize: CGSize {
        CGSize(width: OrbitTokens.Size.expandedWidth, height: Self.height(section: section, detail: detail))
    }

    static func height(section: PanelSection, detail: PanelDetail?) -> CGFloat {
        switch detail {
        case .playlist: return 540
        case .devices: return 372
        case nil: break
        }
        switch section {
        case .player: return 318
        case .picker: return 488
        case .library: return 540
        }
    }
}
