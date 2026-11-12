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

struct PickerContentTests {
    let library = MockFixtures.playlists
    let liked = Playlist(id: LikedSongs.id, name: "Liked Songs", ownerName: "Your library", itemCount: 5, canReadItems: true)

    @Test func pinsComeFirstAndRecentsSkipPins() {
        let content = PickerContent(
            pinned: [library[2]],
            recents: [library[2], library[4], library[5], library[6], library[7], library[8]],
            liked: liked,
            library: library,
            filter: ""
        )
        #expect(content.sections.map(\.title) == ["Pinned", "Recent", "Your Library"])
        #expect(content.sections[1].entries.map(\.playlist.id) == [library[4], library[5], library[6], library[7]].map(\.id))
        #expect(content.sections[2].entries.first?.playlist.id == liked.id)
        #expect(Set(content.keys).count == content.keys.count, "a pinned playlist repeated in the library still has its own key")
    }

    @Test func emptyShelvesLeaveOnlyTheLibrary() {
        let content = PickerContent(pinned: [], recents: [], liked: nil, library: [], filter: "")
        #expect(content.sections.map(\.id) == ["library"])
        #expect(content.keys.isEmpty)
    }

    @Test func filteringSearchesEverythingOnceWithWordStartsFirst() throws {
        let content = PickerContent(pinned: [library[0]], recents: [], liked: liked, library: library, filter: " night ")
        #expect(content.isFiltered)
        let names = try #require(content.sections.first).entries.map(\.playlist.name)
        #expect(names == ["Night Drive", "Late Night Jazz"])
    }

    @Test func wordPrefixOutranksAMatchInsideAWord() {
        let playlists = [
            Playlist(id: "1", name: "Midnight Run", ownerName: "Me", canReadItems: true),
            Playlist(id: "2", name: "Night Shift", ownerName: "Me", canReadItems: true),
            Playlist(id: "3", name: "Late Night", ownerName: "Me", canReadItems: true),
        ]
        #expect(PickerContent.matches(for: "night", in: playlists).map(\.id) == ["2", "3", "1"])
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
        navigator.showLibrary(.liked)
        navigator.footerHeight = 50
        navigator.recordFit(330, for: navigator.fitKey)
        #expect(navigator.screenSize.height == 380)
    }

    @Test func eachLibraryTabKeepsItsOwnFit() {
        let navigator = PanelNavigator()
        navigator.showLibrary(.liked)
        navigator.recordFit(300, for: navigator.fitKey)
        navigator.libraryTab = .queue
        #expect(navigator.screenSize.height == PanelNavigator.height(section: .library, detail: nil))
        navigator.recordFit(420, for: navigator.fitKey)
        navigator.libraryTab = .liked
        #expect(navigator.screenSize.height == 300)
    }

    @Test func screensThatDoNotFitKeepTheirFixedHeight() {
        let navigator = PanelNavigator()
        #expect(navigator.screenSize.height == PanelNavigator.height(section: .player, detail: nil))
    }
}
