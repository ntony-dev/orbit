import CoreGraphics
import OrbitCore
@testable import OrbitUI
import Testing

struct CanvasPlanTests {
    let pill = CGSize(width: 272, height: 52)
    let player = CGSize(width: 344, height: 318)
    let picker = CGSize(width: 344, height: 488)

    @Test func growsBeforeExpandingAndShrinksAfter() {
        let collapsed = CanvasPlan.canvas(for: pill)
        let during = CanvasPlan.during(current: collapsed, target: player)
        #expect(during == CanvasPlan.canvas(for: player))
        #expect(CanvasPlan.after(current: during, target: player) == nil)
    }

    @Test func keepsTheLargerCanvasWhileShrinking() {
        let expanded = CanvasPlan.canvas(for: picker)
        #expect(CanvasPlan.during(current: expanded, target: player) == expanded)
        #expect(CanvasPlan.after(current: expanded, target: player) == CanvasPlan.canvas(for: player))
    }

    @Test func interruptedCollapseNeverClipsTheSurface() {
        // Expanded to the picker, collapse starts, then a re-expansion to the player arrives mid-flight.
        let expanded = CanvasPlan.canvas(for: picker)
        let collapsing = CanvasPlan.during(current: expanded, target: pill)
        let reexpanding = CanvasPlan.during(current: collapsing, target: player)
        #expect(reexpanding.height >= CanvasPlan.canvas(for: picker).height)
    }

    @Test func pillSizesClampTheSurfaceRadiusToACapsule() {
        for size in PillSize.allCases {
            #expect(OrbitTokens.Size.pill(size).height / 2 <= OrbitTokens.Radius.surface)
        }
    }
}

@MainActor
struct PanelNavigatorTests {
    @Test func backStepsOutOneLayerAtATime() {
        let navigator = PanelNavigator()
        navigator.showLibrary(.playlists)
        navigator.push(.playlist(Playlist(id: "a", name: "Mix", ownerName: "Ana", canReadItems: true)))
        #expect(navigator.depth == 2)
        #expect(navigator.back())
        #expect(navigator.section == .library && navigator.detail == nil)
        #expect(navigator.back())
        #expect(navigator.section == .player)
        #expect(!navigator.back())
    }

    @Test func theDeviceListIsALayerThatEscapeClosesFirst() {
        let navigator = PanelNavigator()
        navigator.showsDevices = true
        #expect(navigator.depth == 1)
        #expect(navigator.keyScreen == .player)
        #expect(navigator.back())
        #expect(!navigator.showsDevices)
        #expect(navigator.section == .player)
        #expect(!navigator.back())
    }

    @Test func theDeviceListGrowsThePlayerOnlyWhileItShows() {
        let navigator = PanelNavigator()
        let closed = navigator.screenSize.height
        navigator.devicesHeight = 150
        #expect(navigator.screenSize.height == closed)
        navigator.showsDevices = true
        #expect(navigator.screenSize.height == closed + 150)
        navigator.showsDevices = false
        #expect(navigator.screenSize.height == closed)
    }

    @Test func leavingThePlayerClosesTheDeviceList() {
        let navigator = PanelNavigator()
        navigator.showsDevices = true
        navigator.show(.picker)
        #expect(!navigator.showsDevices)
        navigator.show(.player)
        navigator.showsDevices = true
        navigator.reset(to: .player)
        #expect(!navigator.showsDevices)
        #expect(navigator.depth == 0)
    }

    @Test func directionFollowsSectionOrder() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        #expect(navigator.isForward)
        navigator.show(.picker)
        #expect(!navigator.isForward)
    }

    @Test func externalDestinationsResetTheStack() {
        let navigator = PanelNavigator()
        navigator.showLibrary(.playlists)
        navigator.push(.playlist(Playlist(id: "a", name: "Mix", ownerName: "Ana", canReadItems: true)))
        navigator.reset(to: .playlistPicker)
        #expect(navigator.section == .picker && navigator.detail == nil)
        navigator.reset(to: .search)
        #expect(navigator.section == .library && navigator.libraryTab == .search)
        #expect(navigator.wantsSearchFocus)
    }

    @Test func everyScreenFitsTheCanvasWidth() {
        let sizes = PanelSection.allCases.map { PanelNavigator.height(section: $0, detail: nil) }
        #expect(sizes.allSatisfy { $0 > OrbitTokens.Size.pill(.regular).height })
    }
}

struct FormattingTests {
    @Test func formatsTimes() {
        #expect(Formatting.time(0) == "0:00")
        #expect(Formatting.time(65.9) == "1:05")
        #expect(Formatting.time(3725) == "1:02:05")
        #expect(Formatting.time(-3) == "0:00")
    }

    @Test func describesPlaylists() {
        let mine = Playlist(id: "a", name: "Mix", ownerName: "Ana", itemCount: 1, canReadItems: true)
        let hidden = Playlist(id: "b", name: "Hits", ownerName: "Spotify", canReadItems: false)
        #expect(Formatting.playlistSubtitle(mine) == "Ana · 1 song")
        #expect(Formatting.playlistSubtitle(hidden) == "Spotify")
    }

    @Test func likedSongsUsesTheCollectionContext() throws {
        let liked = try #require(LikedSongs.playlist(for: UserProfile(id: "me"), count: 3))
        #expect(liked.uri.kind == .collection)
        #expect(LikedSongs.contains(liked))
        #expect(Formatting.playlistSubtitle(liked) == "3 songs")
    }
}

struct ThemeTests {
    @Test func backingNeverHidesTheGlassUnlessTransparencyIsReduced() {
        var theme = OrbitTheme.standard
        for preset in GlassPreset.allCases {
            theme.glassPreset = preset
            theme.backgroundOpacity = 1
            #expect(theme.backingOpacity < 0.7)
        }
        theme.reducesTransparency = true
        #expect(theme.backingOpacity > 0.9)
    }

    @Test func increasedContrastRaisesTheFloor() {
        var theme = OrbitTheme.standard
        theme.backgroundOpacity = 0
        #expect(theme.backingOpacity == 0)
        theme.contrast = .increased
        #expect(theme.backingOpacity >= 0.6)
    }
}

@MainActor
struct EscapeTests {
    @Test func escapeClosesLayersBeforeCollapsing() {
        let panel = PanelState()
        panel.expand(to: .playlistPicker)
        panel.openLayerCount = 1
        panel.dismissActiveLayer()
        #expect(panel.isExpanded)
        #expect(panel.layerDismissals == 1)
        panel.openLayerCount = 0
        panel.dismissActiveLayer()
        #expect(!panel.isExpanded)
    }
}
