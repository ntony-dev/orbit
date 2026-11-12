import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

// Starting something new must never bring the Spotify window up: the app's `play track` does, the Web API does not.
@MainActor
struct PlaybackRoutingTests {
    let rig = Rig()
    var coordinator: PlaybackCoordinator { rig.coordinator }
    let target = MockFixtures.playlist("pl-deep-focus")

    // Steps the manual clock while a switch waits for confirmation, the way the real one would pass.
    private func waitingOut(_ start: @escaping @MainActor () async -> Bool) async -> Bool {
        let task = Task { await start() }
        for _ in 0..<16 {
            rig.clock.advance(by: 0.5)
            await settle()
        }
        return await task.value
    }

    private func begin(window: MockSpotify.Window = .minimized) async {
        await rig.spotify.setWindow(window)
        coordinator.start()
        await coordinator.refresh()
    }

    @Test func aSwitchOnTheActiveMacGoesThroughTheWebAPIWithoutRaisingSpotify() async {
        await begin()
        #expect(coordinator.authority == .local)
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.webRequests("play") == 1)
        #expect(await rig.localCommands("play track") == 0)
        // The Web API already named this Mac as the active device, so no device lookup was needed.
        #expect(await rig.webRequests("devices") == 0)
        #expect(await rig.spotify.windowRaises == 0)
        #expect(await rig.spotify.window == .minimized)
        #expect(coordinator.snapshot.context?.uri == target.uri)
    }

    @Test func anIdleMacIsAddressedByItsDeviceID() async {
        await rig.spotify.simulateIdleLocalDevice()
        await begin()
        #expect(coordinator.authority == .local)
        #expect(coordinator.snapshot.isPlaying == false)
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(coordinator.lastError == nil)
        #expect(await rig.webRequests("devices") == 1)
        #expect(await rig.webRequests("play") == 1)
        #expect(await rig.localCommands("play track") == 0)
        #expect(await rig.spotify.windowRaises == 0)
        #expect(coordinator.snapshot.device?.id == MockFixtures.localDevice.id)
        #expect(coordinator.snapshot.context?.uri == target.uri)

        // The device ID is remembered, so later switches cost no lookup.
        await rig.spotify.simulateIdleLocalDevice()
        let other = MockFixtures.playlist("pl-gym")
        #expect(await waitingOut { await coordinator.play(playlist: other) })
        #expect(await rig.webRequests("devices") == 1)
        #expect(await rig.spotify.windowRaises == 0)
    }

    @Test func tracksFromAListOrSearchStartThroughTheWebAPI() async throws {
        await rig.spotify.simulateIdleLocalDevice()
        await begin()
        let coordinator = coordinator
        let inPlaylist = try #require(MockFixtures.playlistTracks[target.id]?[2])
        let target = target
        #expect(await waitingOut { await coordinator.play(track: inPlaylist, in: target.uri) })
        let single = try #require(MockFixtures.track(id: "al-linen-1"))
        #expect(await waitingOut { await coordinator.play(track: single) })
        #expect(coordinator.snapshot.track?.uri == single.uri)
        #expect(await rig.webRequests("play") == 2)
        #expect(await rig.localCommands("play track") == 0)
        #expect(await rig.spotify.windowRaises == 0)
    }

    @Test func aDeviceIDSpotifyNoLongerKnowsIsLookedUpAgain() async {
        await begin()
        await rig.spotify.changeLocalDeviceID(to: "dev-mac-relinked")
        await rig.spotify.simulateIdleLocalDevice()
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.webRequests("devices") == 1)
        #expect(await rig.webRequests("play") == 2)
        #expect(await rig.localCommands("play track") == 0)
        #expect(coordinator.snapshot.device?.id == "dev-mac-relinked")
    }

    @Test func aMacMissingFromSpotifyConnectFallsBackToTheAppAndHidesItAgain() async {
        await rig.spotify.removeLocalDeviceFromConnect()
        await begin()
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.webRequests("play") == 0)
        #expect(await rig.localCommands("play track") == 1)
        #expect(await rig.spotify.windowRaises == 1)
        #expect(await rig.spotify.window == .hidden)
        #expect(coordinator.snapshot.context?.uri == target.uri)
    }

    @Test func signedOutSwitchesThroughTheAppAndHidesAWindowThatWasNotShowing() async {
        coordinator.setWebAPIAvailable(false)
        await begin(window: .hidden)
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.spotify.webRequests.isEmpty)
        #expect(await rig.localCommands("play track") == 1)
        #expect(await rig.spotify.window == .hidden)
        #expect(coordinator.snapshot.context?.uri == target.uri)
    }

    @Test func aWindowTheUserHadOpenIsLeftAlone() async {
        coordinator.setWebAPIAvailable(false)
        await begin(window: .visible)
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.localCommands("play track") == 1)
        #expect(await rig.spotify.window == .visible)
    }

    @Test func aRateLimitedWebAPIFallsBackToTheApp() async {
        await begin()
        await rig.spotify.failWebAPI(with: .rateLimited(retryAfter: 30))
        await coordinator.refresh()
        #expect(coordinator.webAPIPausedUntil != nil)
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.webRequests("play") == 0)
        #expect(await rig.localCommands("play track") == 1)
        #expect(await rig.spotify.window == .hidden)
    }

    // An unusable route falls back; a refusal on the item's merits does not, since the app would refuse it too.
    @Test func onlyRouteFailuresFallBackToTheApp() async {
        await begin()
        await rig.spotify.failWebRequest("play", with: .premiumRequired)
        let coordinator = coordinator
        let target = target
        #expect(await waitingOut { await coordinator.play(playlist: target) })
        #expect(await rig.localCommands("play track") == 1)

        await rig.spotify.failWebRequest("play", with: .contentRestricted)
        let other = MockFixtures.playlist("pl-gym")
        #expect(await waitingOut { await coordinator.play(playlist: other) } == false)
        #expect(coordinator.lastError == .contentRestricted)
        #expect(await rig.localCommands("play track") == 1)
    }

    @Test func plainTransportStaysOnTheApp() async {
        await begin()
        await coordinator.togglePlayPause()
        await coordinator.togglePlayPause()
        await coordinator.seek(to: 30)
        await coordinator.setVolume(40)
        await coordinator.next()
        await coordinator.previous()
        #expect(await rig.localCommands("pause") == 1)
        #expect(await rig.localCommands("play") == 1)
        #expect(await rig.localCommands("next track") == 1)
        #expect(await rig.localCommands("previous track") == 1)
        #expect(await rig.localCommands("set player position") == 1)
        #expect(await rig.localCommands("set sound volume") == 1)
        let commands = ["pause", "resume", "skipToNext", "skipToPrevious", "seek", "setVolume"]
        #expect(await rig.spotify.webRequests.filter(commands.contains).isEmpty)
    }
}
