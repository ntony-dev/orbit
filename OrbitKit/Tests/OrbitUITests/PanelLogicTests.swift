import CoreGraphics
import Observation
import OrbitCore
@testable import OrbitUI
import SwiftUI
import Synchronization
import Testing

struct CanvasPlanTests {
    let pill = CGSize(width: 272, height: 52)
    let player = CGSize(width: 344, height: 318)
    let library = CGSize(width: 344, height: 488)

    @Test func growsBeforeExpandingAndShrinksAfter() {
        let collapsed = CanvasPlan.canvas(for: pill)
        let during = CanvasPlan.during(current: collapsed, target: player)
        #expect(during == CanvasPlan.canvas(for: player))
        #expect(CanvasPlan.after(current: during, target: player) == nil)
    }

    @Test func keepsTheLargerCanvasWhileShrinking() {
        let expanded = CanvasPlan.canvas(for: library)
        #expect(CanvasPlan.during(current: expanded, target: player) == expanded)
        #expect(CanvasPlan.after(current: expanded, target: player) == CanvasPlan.canvas(for: player))
    }

    @Test func interruptedCollapseNeverClipsTheSurface() {
        // Expanded to the library, collapse starts, then a re-expansion to the player arrives mid-flight.
        let expanded = CanvasPlan.canvas(for: library)
        let collapsing = CanvasPlan.during(current: expanded, target: pill)
        let reexpanding = CanvasPlan.during(current: collapsing, target: player)
        #expect(reexpanding.height >= CanvasPlan.canvas(for: library).height)
    }

    @Test func pillSizesClampTheSurfaceRadiusToACapsule() {
        for size in PillSize.allCases {
            #expect(OrbitTokens.Size.pill(size).height / 2 <= OrbitTokens.Radius.surface)
        }
    }
}

@MainActor
struct PanelNavigatorTests {
    let mix = Playlist(id: "a", name: "Mix", ownerName: "Ana", canReadItems: true)

    @Test func backStepsOutOneLayerAtATime() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        navigator.push(.playlist(mix))
        #expect(navigator.depth == 2)
        #expect(navigator.back())
        #expect(navigator.section == .library && navigator.detail == nil)
        #expect(navigator.back())
        #expect(navigator.section == .player)
        #expect(!navigator.back())
    }

    @Test func aDrawerIsALayerThatEscapeClosesFirst() {
        for drawer in [PlayerDrawer.devices, .queue] {
            let navigator = PanelNavigator()
            navigator.toggle(drawer)
            #expect(navigator.depth == 1)
            #expect(navigator.keyScreen == .player)
            #expect(navigator.back())
            #expect(navigator.drawer == nil)
            #expect(navigator.section == .player)
            #expect(!navigator.back())
        }
    }

    @Test func theSameButtonClosesItsDrawerAndTheOtherReplacesIt() {
        let navigator = PanelNavigator()
        navigator.toggle(.queue)
        #expect(navigator.drawer == .queue)
        navigator.toggle(.devices)
        #expect(navigator.drawer == .devices, "only one drawer is open at a time")
        navigator.close(.queue)
        #expect(navigator.drawer == .devices, "a drawer only closes itself")
        navigator.toggle(.devices)
        #expect(navigator.drawer == nil)
    }

    @Test func aDrawerGrowsThePlayerByItsOwnHeightOnlyWhileItShows() {
        let navigator = PanelNavigator()
        let closed = navigator.screenSize.height
        navigator.recordDrawerHeight(150, for: .devices)
        navigator.recordDrawerHeight(230, for: .queue)
        #expect(navigator.screenSize.height == closed)
        navigator.toggle(.devices)
        #expect(navigator.screenSize.height == closed + 150)
        navigator.toggle(.queue)
        #expect(navigator.screenSize.height == closed + 230)
        navigator.toggle(.queue)
        #expect(navigator.screenSize.height == closed)
    }

    @Test func leavingThePlayerClosesItsDrawer() {
        let navigator = PanelNavigator()
        navigator.toggle(.queue)
        navigator.show(.library)
        #expect(navigator.drawer == nil)
        navigator.show(.player)
        navigator.toggle(.devices)
        navigator.reset(to: .player)
        #expect(navigator.drawer == nil)
        #expect(navigator.depth == 0)
    }

    @Test func directionFollowsSectionOrder() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        #expect(navigator.isForward)
        navigator.show(.player)
        #expect(!navigator.isForward)
    }

    @Test func thePickerDestinationOpensTheLibraryFromTheTop() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        navigator.searchQuery = "night"
        navigator.push(.playlist(mix))
        navigator.reset(to: .playlistPicker)
        #expect(navigator.section == .library && navigator.detail == nil)
        #expect(navigator.searchQuery.isEmpty)
        #expect(!navigator.wantsSearchFocus)
    }

    @Test func theSearchDestinationOpensTheLibraryWithItsFieldFocused() {
        let navigator = PanelNavigator()
        navigator.searchQuery = "night"
        navigator.toggle(.devices)
        navigator.reset(to: .search)
        #expect(navigator.section == .library && navigator.detail == nil && navigator.drawer == nil)
        #expect(navigator.wantsSearchFocus)
        #expect(navigator.searchQuery == "night")
    }

    @Test func glancingAtThePlayerKeepsTheQuery() {
        let navigator = PanelNavigator()
        navigator.show(.library)
        navigator.searchQuery = "night"
        navigator.show(.player)
        navigator.show(.library)
        #expect(navigator.searchQuery == "night")
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
            #expect(theme.surfaceFill(for: .light) < 0.9)
            #expect(theme.surfaceFill(for: .dark) < 0.9)
        }
        theme.reducesTransparency = true
        #expect(theme.surfaceFill(for: .dark) > 0.9)
    }

    @Test func increasedContrastRaisesTheFloor() {
        var theme = OrbitTheme.standard
        theme.backgroundOpacity = 0
        #expect(theme.surfaceFill(for: .light) < 0.5)
        theme.contrast = .increased
        #expect(theme.surfaceFill(for: .light) >= 0.8)
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

@MainActor
struct ArtworkTintTests {
    // The root view rebuilds the theme for every view whenever something it read changes.
    private func changes(reading preset: GlassPreset, when tint: ArtworkTint, becomes color: Color) -> Bool {
        let changed = Mutex(false)
        withObservationTracking {
            _ = tint.color(for: preset)
        } onChange: {
            changed.withLock { $0 = true }
        }
        tint.color = color
        return changed.withLock { $0 }
    }

    @Test func onlyTheTintedPresetObservesTheCoverTint() {
        let tint = ArtworkTint()
        #expect(!changes(reading: .balanced, when: tint, becomes: .red))
        #expect(!changes(reading: .clear, when: tint, becomes: .blue))
        #expect(changes(reading: .tinted, when: tint, becomes: .green))
        #expect(tint.color(for: .tinted) == .green)
        #expect(tint.color(for: .balanced) == nil)
    }
}
