import CoreGraphics
import OrbitCore
import OrbitMocks
@testable import OrbitUI
import Testing

struct KeyboardSelectionTests {
    let keys = ["a", "b", "c"]

    @Test func downStartsAtTheTopAndUpAtTheBottom() {
        var down = KeyboardSelection()
        down.move(1, in: keys)
        #expect(down.key == "a")
        var up = KeyboardSelection()
        up.move(-1, in: keys)
        #expect(up.key == "c")
    }

    @Test func movesOneRowAndStopsAtTheEnds() {
        var selection = KeyboardSelection()
        selection.move(1, in: keys)
        selection.move(1, in: keys)
        #expect(selection.key == "b")
        selection.move(1, in: keys)
        selection.move(1, in: keys)
        #expect(selection.key == "c")
        selection.move(-5, in: keys)
        #expect(selection.key == "a")
    }

    @Test func anEmptyListHasNoSelection() {
        var selection = KeyboardSelection()
        selection.move(1, in: keys)
        selection.move(1, in: [])
        #expect(selection.key == nil)
    }

    @Test func aHiddenRowDropsTheSelection() {
        var selection = KeyboardSelection()
        selection.move(-1, in: keys)
        selection.reconcile(with: ["a", "c"])
        #expect(selection.key == "c")
        selection.reconcile(with: ["a"])
        #expect(selection.key == nil)
    }

    @Test func returnFallsBackToTheTopMatchOnlyWhenAsked() {
        var selection = KeyboardSelection()
        #expect(selection.target(in: keys, fallsBackToFirst: false) == nil)
        #expect(selection.target(in: keys, fallsBackToFirst: true) == "a")
        selection.move(-1, in: keys)
        #expect(selection.target(in: keys, fallsBackToFirst: true) == "c")
        #expect(selection.target(in: ["a"], fallsBackToFirst: false) == nil)
    }
}

struct LibraryContentTests {
    let library = MockFixtures.playlists
    let liked = Playlist(id: LikedSongs.id, name: "Liked Songs", ownerName: "Your library", itemCount: 5, canReadItems: true)

    private func ids(_ section: LibraryContent.Section) -> [String] {
        section.entries.compactMap { $0.item.opensTracks?.id }
    }

    @Test func pinsComeFirstThenAtMostThreeRecentsThatAreNotPinned() {
        let content = LibraryContent(
            pinned: [library[2]],
            recents: [library[2], library[4], library[5], library[6], library[7]],
            liked: liked,
            library: library,
            query: ""
        )
        #expect(content.sections.map(\.title) == ["Pinned", "Recent", "Your Library"])
        #expect(ids(content.sections[0]) == [library[2].id])
        #expect(ids(content.sections[1]) == [library[4], library[5], library[6]].map(\.id))
        #expect(content.spotify.isEmpty)
    }

    @Test func likedSongsLeadsTheLibraryWhichNeverRepeatsAPinOrARecent() {
        let content = LibraryContent(pinned: [library[2]], recents: [library[4]], liked: liked, library: library, query: "")
        let rest = ids(content.sections[2])
        #expect(rest.first == liked.id)
        #expect(!rest.contains(library[2].id) && !rest.contains(library[4].id))
        #expect(rest.count == library.count + 1 - 2)
        let keyed = content.keys.compactMap { content.entry(for: $0)?.item.opensTracks?.id }
        #expect(Set(keyed).count == keyed.count, "every playlist appears once")
    }

    @Test func aPinnedLikedSongsLeavesTheLibrarySection() {
        let content = LibraryContent(pinned: [liked], recents: [], liked: liked, library: library, query: "")
        #expect(ids(content.sections[0]) == [liked.id])
        #expect(ids(content.sections[1]).first == library[0].id)
    }

    @Test func emptySectionsDoNotAppear() {
        #expect(LibraryContent(pinned: [], recents: [], liked: nil, library: [], query: "").sections.isEmpty)
        let onlyLiked = LibraryContent(pinned: [], recents: [], liked: liked, library: [], query: "")
        #expect(onlyLiked.sections.map(\.id) == ["library"])
        let recentsAllPinned = LibraryContent(pinned: [library[0]], recents: [library[0]], liked: nil, library: library, query: "")
        #expect(recentsAllPinned.sections.map(\.id) == ["pinned", "library"])
    }

    @Test func filteringMatchesTheUsersPlaylistsOnceWithWordStartsFirst() throws {
        let content = LibraryContent(pinned: [library[0]], recents: [], liked: liked, library: library, query: " night ")
        #expect(content.isFiltered)
        #expect(content.query == "night")
        let matches = try #require(content.sections.first)
        #expect(matches.title == "Your Library")
        #expect(matches.entries.compactMap { $0.item.opensTracks?.name } == ["Night Drive", "Late Night Jazz"])
    }

    @Test func spotifyResultsFollowTheMatchesAndSkipPlaylistsAlreadyListed() {
        let results = SearchResults(
            tracks: Array(MockFixtures.tracks.prefix(2)),
            albums: [MockFixtures.albums[0]],
            playlists: [library[0], library[6]]
        )
        let content = LibraryContent(pinned: [], recents: [], liked: liked, library: library, query: "night", results: results)
        #expect(content.spotify.map(\.title) == ["Songs", "Albums", "Playlists"])
        #expect(ids(content.spotify[2]) == [library[6].id], "Night Drive is already among the user's matches")
        #expect(content.keys == ["match:pl-night-drive", "match:pl-late-jazz", "track:0", "track:1", "album:al-neon-harbor", "spotify:pl-top-hits"])
    }

    @Test func clearingTheQueryReturnsToTheNormalListAndIgnoresStaleResults() {
        let results = SearchResults(tracks: Array(MockFixtures.tracks.prefix(1)))
        let content = LibraryContent(pinned: [], recents: [], liked: liked, library: library, query: "  ", results: results)
        #expect(!content.isFiltered)
        #expect(content.spotify.isEmpty)
        #expect(content.sections.map(\.id) == ["library"])
    }

    // Return plays any row; only playlists, Liked Songs and Spotify's playlists also open into a track list, from
    // a click on the row or Right Arrow. Songs and albums only play.
    @Test func onlyPlaylistRowsOpenIntoTracks() {
        let results = SearchResults(tracks: [MockFixtures.tracks[0]], albums: [MockFixtures.albums[0]], playlists: [library[6]])
        let content = LibraryContent(pinned: [], recents: [], liked: liked, library: library, query: "drive", results: results)
        #expect(content.entry(for: "track:0")?.item.opensTracks == nil)
        #expect(content.entry(for: "album:al-neon-harbor")?.item.opensTracks == nil)
        #expect(content.entry(for: "spotify:pl-top-hits")?.item.opensTracks?.id == "pl-top-hits")
        let normal = LibraryContent(pinned: [], recents: [], liked: liked, library: library, query: "")
        #expect(normal.entry(for: "library:\(LikedSongs.id)")?.item.opensTracks == liked)
    }

    @Test func recentsCarryTheirRemoveFromRecentsAction() {
        let content = LibraryContent(pinned: [], recents: [library[3]], liked: nil, library: library, query: "")
        #expect(content.entry(for: "recent:\(library[3].id)")?.item == .playlist(library[3], isRecent: true))
        #expect(content.entry(for: "library:\(library[0].id)")?.item == .playlist(library[0], isRecent: false))
        let filtered = LibraryContent(pinned: [], recents: [library[3]], liked: nil, library: library, query: library[3].name)
        #expect(filtered.entry(for: "match:\(library[3].id)")?.item == .playlist(library[3], isRecent: true))
    }

    @Test func wordPrefixOutranksAMatchInsideAWord() {
        let playlists = [
            Playlist(id: "1", name: "Midnight Run", ownerName: "Me", canReadItems: true),
            Playlist(id: "2", name: "Night Shift", ownerName: "Me", canReadItems: true),
            Playlist(id: "3", name: "Late Night", ownerName: "Me", canReadItems: true),
        ]
        #expect(LibraryContent.matches(for: "night", in: playlists).map(\.id) == ["2", "3", "1"])
    }
}

@MainActor
struct PanelFitTests {
    @Test func fallsBackWhenAScreenHasNotMeasuredItself() {
        #expect(PanelNavigator.fittedHeight(natural: nil, fallback: 318) == 318)
    }

    @Test func clampsToSensibleBounds() {
        #expect(PanelNavigator.fittedHeight(natural: 120, fallback: 540) == OrbitTokens.Size.fittedMinHeight)
        #expect(PanelNavigator.fittedHeight(natural: 2_000, fallback: 540) == OrbitTokens.Size.fittedMaxHeight)
        #expect(PanelNavigator.fittedHeight(natural: 400.2, fallback: 540) == 401)
    }

    @Test func aShortListShrinksTheSurfaceAndTheFooterCounts() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        navigator.footerHeight = 50
        navigator.recordFit(330, for: navigator.fitKey)
        #expect(navigator.screenSize.height == 380)
    }

    @Test func theLibraryAndATrackListKeepTheirOwnFits() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        navigator.recordFit(300, for: navigator.fitKey)
        navigator.push(.playlist(MockFixtures.playlists[0]))
        #expect(navigator.screenSize.height == PanelNavigator.height(section: .library, detail: navigator.detail))
        navigator.recordFit(420, for: navigator.fitKey)
        navigator.back()
        #expect(navigator.screenSize.height == 300)
    }

    @Test func screensThatDoNotFitKeepTheirFixedHeight() {
        let navigator = PanelNavigator()
        #expect(navigator.screenSize.height == PanelNavigator.height(section: .player, detail: nil))
    }
}
