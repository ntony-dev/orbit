import CoreGraphics
import Foundation
import Observation
import OrbitCore

enum PanelSection: Int, CaseIterable, Hashable {
    case player, library
}

// A layer pushed over a section: a playlist's tracks, opened from the library.
enum PanelDetail: Hashable {
    case playlist(Playlist)
}

// What the player reveals in place under its volume row. One at a time, so opening one closes the other.
enum PlayerDrawer: Hashable {
    case devices, queue
}

// Where the expanded surface is. Owned by the UI alone; the shell only expresses an initial destination through
// PanelState.requestedDestination.
@MainActor
@Observable
final class PanelNavigator {
    private(set) var section: PanelSection = .player
    private(set) var detail: PanelDetail?
    // The library's search field. Kept here rather than in the library so glancing at the player and coming
    // back keeps the query and its results.
    var searchQuery = ""
    // Which way the last move went, so the incoming screen slides in from the side the user is heading toward.
    private(set) var isForward = true
    // A drawer counts as a layer, so Escape closes it before anything else and the pointer never has to travel
    // to a back button.
    var drawer: PlayerDrawer?
    // Each drawer's height, reported by the drawer, which the player's surface grows by while it shows. Kept per
    // drawer so the outgoing one, still fading, never sizes the surface for the incoming one.
    private(set) var drawerHeights: [PlayerDrawer: CGFloat] = [:]
    // Set when the user (or a focus-search shortcut) asked to type a search. Taking focus makes the panel key, so
    // search never focuses merely because it appeared.
    var wantsSearchFocus = false

    // The focused search field, written only by that field. During a transition two fields can be on screen for
    // a moment, so each clears only its own claim.
    private(set) var textFieldFocus: TextFieldFocus?
    private var textFieldOwner: UUID?

    var depth: Int {
        (section == .player ? 0 : 1) + (detail == nil ? 0 : 1) + (drawer == nil ? 0 : 1)
    }

    var keyScreen: PanelKeyScreen {
        switch (detail, section) {
        case (.playlist, _): .trackList
        case (nil, .player): .player
        case (nil, .library): .list
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
        drawer = nil
    }

    func push(_ newDetail: PanelDetail) {
        isForward = true
        detail = newDetail
        drawer = nil
    }

    // The same click that opened a drawer closes it; opening one replaces the other.
    func toggle(_ newDrawer: PlayerDrawer) {
        drawer = drawer == newDrawer ? nil : newDrawer
    }

    func close(_ closing: PlayerDrawer) {
        if drawer == closing { drawer = nil }
    }

    func recordDrawerHeight(_ height: CGFloat, for drawer: PlayerDrawer) {
        guard drawerHeights[drawer] != height else { return }
        drawerHeights[drawer] = height
    }

    // Steps back one layer and reports whether there was one to leave.
    @discardableResult
    func back() -> Bool {
        isForward = false
        if drawer != nil {
            drawer = nil
            return true
        }
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

    // The picker destination is a request for the place to pick music, so it starts from the full list rather
    // than a query left from earlier; the search destination keeps the query and puts the caret in it.
    func reset(to destination: PanelDestination) {
        isForward = true
        detail = nil
        drawer = nil
        switch destination {
        case .player:
            section = .player
        case .playlistPicker:
            searchQuery = ""
            section = .library
        case .search:
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
        FitKey(section: section, detail: detail)
    }

    func recordFit(_ height: CGFloat, for key: FitKey) {
        guard fittedHeights[key] != height else { return }
        fittedHeights[key] = height
    }

    // The surface size for the current screen: its fitted height when it has reported one, otherwise the
    // fixed height of the first pass, which is also the ceiling for screens that cannot fit (the player), plus
    // the open drawer while the player shows one.
    var screenSize: CGSize {
        let height = Self.fittedHeight(
            natural: fittedHeights[fitKey].map { $0 + footerHeight },
            fallback: Self.height(section: section, detail: detail)
        )
        let drawerHeight = drawer.flatMap { drawerHeights[$0] } ?? 0
        return CGSize(width: OrbitTokens.Size.expandedWidth, height: height + drawerHeight)
    }

    static func fittedHeight(natural: CGFloat?, fallback: CGFloat) -> CGFloat {
        guard let natural else { return fallback }
        return min(OrbitTokens.Size.fittedMaxHeight, max(OrbitTokens.Size.fittedMinHeight, natural.rounded(.up)))
    }

    static func height(section: PanelSection, detail: PanelDetail?) -> CGFloat {
        if case .playlist = detail { return 540 }
        switch section {
        case .player: return OrbitTokens.Size.playerHeight
        case .library: return 540
        }
    }
}

struct FitKey: Hashable {
    let section: PanelSection
    let detail: PanelDetail?
}
