import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

@MainActor
struct PlaylistSwitchTests {
    let rig = Rig()
    let stores: OrbitStores
    var playback: PlaybackCoordinator { stores.playback }
    let target = MockFixtures.playlist("pl-deep-focus")

    init() async throws {
        stores = rig.stores()
        stores.start()
        let stores = stores
        let ready = await eventually {
            stores.library.playlists.value != nil && stores.library.likedSongs != nil
                && stores.playback.snapshot.context != nil && stores.playback.authority == .local
        }
        try #require(ready)
    }

    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func pendingShowsAtOnceAndSuccessIsConfirmedFromObservedState() async {
        await rig.spotify.holdCommands()
        let playback = playback
        let target = target
        let switching = Task { await playback.play(playlist: target) }
        #expect(await eventually { playback.pendingIntents.contains(.playContext(target.uri)) })
        #expect(playback.snapshot.context?.uri == MockFixtures.startingPlaylist.uri)
        #expect(stores.library.recentPlaylists.isEmpty)

        await rig.spotify.releaseCommands()
        #expect(await switching.value)
        #expect(playback.snapshot.context?.uri == target.uri)
        #expect(playback.snapshot.context?.name == target.name)
        #expect(playback.pendingIntents.isEmpty)
        #expect(playback.lastError == nil)
        #expect(stores.library.recentPlaylists.first?.id == target.id)
        #expect(await rig.localCommands("play track") == 1)
    }

    @Test func playlistsWithUnreadableItemsStillSwitch() async {
        let hidden = MockFixtures.playlists.first { !$0.canReadItems }!
        #expect(await playback.play(playlist: hidden))
        #expect(playback.snapshot.context?.uri == hidden.uri)
        #expect(stores.library.recentPlaylists.first?.id == hidden.id)
    }

    @Test func likedSongsSwitchesAsTheCollectionContext() async throws {
        let liked = try #require(stores.library.likedSongs)
        #expect(await playback.play(playlist: liked))
        #expect(playback.snapshot.context?.uri.kind == .collection)
        #expect(playback.snapshot.context?.name == LikedSongs.name)
        #expect(stores.library.recentPlaylists.first?.id == LikedSongs.playlistID)
    }

    @Test func aRefusedSwitchClearsPendingAndReportsTheError() async {
        await rig.spotify.failLocalCommands(with: .contentRestricted)
        #expect(await playback.play(playlist: target) == false)
        #expect(playback.lastError == .contentRestricted)
        #expect(playback.pendingIntents.isEmpty)
        #expect(playback.snapshot.context?.uri == MockFixtures.startingPlaylist.uri)
        #expect(stores.library.recentPlaylists.isEmpty)
    }

    @Test func anAcceptedButUnobservedSwitchTimesOutAsAFailure() async {
        await rig.spotify.ignorePlayCommands(true)
        let playback = playback
        let target = target
        let switching = Task { await playback.play(playlist: target) }
        #expect(await eventually { await rig.localCommands("play track") == 1 })
        for _ in 0..<8 {
            rig.clock.advance(by: 1)
            await settle()
        }
        #expect(await switching.value == false)
        #expect(playback.lastError == .playbackNotConfirmed)
        #expect(playback.pendingIntents.isEmpty)
        #expect(playback.snapshot.context?.uri == MockFixtures.startingPlaylist.uri)
        #expect(stores.library.recentPlaylists.isEmpty)
    }

    @Test func aNewerSwitchSupersedesAnOlderOneQuietly() async {
        let first = MockFixtures.playlist("pl-gym")
        await rig.spotify.holdCommands()
        let playback = playback
        let target = target
        let older = Task { await playback.play(playlist: first) }
        #expect(await eventually { await rig.spotify.heldCommandCount == 1 })
        let newer = Task { await playback.play(playlist: target) }
        #expect(await eventually { playback.pendingIntents.contains(.playContext(target.uri)) })
        await rig.spotify.releaseCommands()
        #expect(await older.value == false)
        #expect(await newer.value)
        #expect(playback.lastError == nil)
        #expect(playback.snapshot.context?.uri == target.uri)
        #expect(stores.library.recentPlaylists.map(\.id) == [target.id])
    }

    @Test func aStateNotificationRacingTheSwitchCannotRevertIt() async throws {
        await rig.spotify.holdCommands()
        let playback = playback
        let target = target
        let switching = Task { await playback.play(playlist: target) }
        #expect(await eventually { await rig.spotify.heldCommandCount == 1 })

        var stale = try #require(await rig.spotify.currentLocalState())
        stale.track = MockFixtures.playlistTracks[MockFixtures.startingPlaylist.id]?[1]
        stale.position = 0
        await rig.spotify.emitLocalState(stale)
        await settle()
        #expect(playback.pendingIntents.contains(.playContext(target.uri)))
        #expect(playback.snapshot.context?.uri == MockFixtures.startingPlaylist.uri)

        await rig.spotify.releaseCommands()
        #expect(await switching.value)
        #expect(playback.snapshot.context?.uri == target.uri)

        await rig.spotify.emitLocalState(stale)
        await settle()
        #expect(playback.snapshot.context?.uri == target.uri)
    }

    @Test func switchesThroughTheWebAPIWhenAutomationIsDenied() async {
        await rig.spotify.setAutomationPermission(.denied)
        await playback.refresh()
        let playback = playback
        let target = target
        let switching = Task { await playback.play(playlist: target) }
        for _ in 0..<6 {
            rig.clock.advance(by: 0.5)
            await settle()
        }
        #expect(await switching.value)
        #expect(await rig.webRequests("play") == 1)
        #expect(await rig.localCommands("play track") == 0)
        #expect(playback.snapshot.context?.uri == target.uri)
    }
}

// Real time and simulated latency, as `--demo` runs, to catch anything the manual clock hides.
@MainActor
struct DemoSmokeTests {
    @Test func switchesAndSkipsWithRealTimeAndLatency() async throws {
        let spotify = MockSpotify(latency: .milliseconds(30))
        let services = MockServices(spotify: spotify, authorizer: MockAuthorizer(latency: .zero))
        let stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        stores.start()
        stores.setInterfaceVisibility(.expanded)
        try #require(await eventually { stores.playback.snapshot.context?.name == "Night Drive" })

        let target = MockFixtures.playlist("pl-late-jazz")
        #expect(await stores.playback.play(playlist: target))
        #expect(stores.playback.snapshot.context?.name == target.name)
        let tracks = MockFixtures.playlistTracks[target.id] ?? []
        #expect(stores.playback.snapshot.track.map(tracks.contains) == true)

        let before = stores.playback.snapshot.track
        await stores.playback.next()
        #expect(stores.playback.snapshot.track != before)
        #expect(stores.playback.lastError == nil)
        stores.playback.stop()
    }
}
