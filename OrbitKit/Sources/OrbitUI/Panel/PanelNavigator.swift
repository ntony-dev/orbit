import CoreGraphics
import Foundation
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
    // Set when the user (or a focus-search shortcut) asked to type a search. Taking focus makes the panel key, so
    // search never focuses merely because it appeared.
    var wantsSearchFocus = false

    // The focused search or filter field, written only by that field. During a transition two fields can be on
    // screen for a moment, so each clears only its own claim.
    private(set) var textFieldFocus: TextFieldFocus?
    private var textFieldOwner: UUID?

    var depth: Int {
        (section == .player ? 0 : 1) + (detail == nil ? 0 : 1)
    }

    var keyScreen: PanelKeyScreen {
        switch (detail, section) {
        case (.playlist, _): .list
        case (.devices, _): .other
        case (nil, .player): .player
        case (nil, .picker): .list
        case (nil, .library): libraryTab == .queue ? .other : .list
        }
    }

    func setTextFieldFocus(_ focus: TextFieldFocus?, owner: UUID) {
        if let focus {
            textFieldOwner = owner
            textFieldFocus = focus
        } else if textFieldOwner == owner {
            textFieldOwner = nil
            textFieldFocus = nil
        }
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
            wantsSearchFocus = true
        }
    }

    // Natural heights reported by fitted screens, keyed by what they show, so revisiting a screen morphs straight
    // to its size instead of passing through the fallback first.
    private var fittedHeights: [FitKey: CGFloat] = [:]
    // Everything the expanded surface draws below the active screen (the section switcher and its padding).
    var footerHeight: CGFloat = 0

    var fitKey: FitKey {
        FitKey(section: section, detail: detail, libraryTab: section == .library && detail == nil ? libraryTab : nil)
    }

    func recordFit(_ height: CGFloat, for key: FitKey) {
        guard fittedHeights[key] != height else { return }
        fittedHeights[key] = height
    }

    // The surface size for the current screen: its fitted height when it has reported one, otherwise the
    // fixed height of the first pass, which is also the ceiling for screens that cannot fit (player, devices).
    var screenSize: CGSize {
        CGSize(width: OrbitTokens.Size.expandedWidth, height: Self.fittedHeight(
            natural: fittedHeights[fitKey].map { $0 + footerHeight },
            fallback: Self.height(section: section, detail: detail)
        ))
    }

    static func fittedHeight(natural: CGFloat?, fallback: CGFloat) -> CGFloat {
        guard let natural else { return fallback }
        return min(OrbitTokens.Size.fittedMaxHeight, max(OrbitTokens.Size.fittedMinHeight, natural.rounded(.up)))
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

struct FitKey: Hashable {
    let section: PanelSection
    let detail: PanelDetail?
    let libraryTab: LibraryTab?
}
