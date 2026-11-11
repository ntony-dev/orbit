import Foundation
import OrbitCore
import OrbitEngine
import OrbitMocks
import Synchronization
import Testing

final class TestClock: Sendable {
    private let date = Mutex(Date(timeIntervalSinceReferenceDate: 0))

    var now: @Sendable () -> Date { { [self] in date.withLock { $0 } } }

    func advance(by seconds: TimeInterval) {
        date.withLock { $0.addTimeInterval(seconds) }
    }
}

@MainActor
struct PlaybackCoordinatorTests {
    let clock = TestClock()
    let services: MockServices
    let coordinator: PlaybackCoordinator

    init() {
        services = MockServices(spotify: MockSpotify(latency: .zero, now: clock.now), authorizer: MockAuthorizer(latency: .zero))
        coordinator = PlaybackCoordinator(localPlayer: services.localPlayer, api: services.api)
    }

    @Test func refreshLoadsTheSimulatedSnapshot() async {
        await coordinator.refresh()
        #expect(coordinator.snapshot.track?.name == "Afterglow Avenue")
        #expect(coordinator.snapshot.isPlaying)
        #expect(coordinator.snapshot.context?.name == "Night Drive")
        #expect(coordinator.snapshot.allows(.skipNext))
        #expect(coordinator.isCurrentTrackSaved == true)
    }

    @Test func togglePlayPauseRoundTrips() async {
        await coordinator.refresh()
        await coordinator.togglePlayPause()
        #expect(!coordinator.snapshot.isPlaying)
        await coordinator.togglePlayPause()
        #expect(coordinator.snapshot.isPlaying)
        #expect(coordinator.pendingIntents.isEmpty)
    }

    @Test func nextPlaysTheUserQueueFirst() async {
        await coordinator.refresh()
        await coordinator.next()
        #expect(coordinator.snapshot.track?.id == MockFixtures.queuedTrackIDs[0])
    }

    @Test func playingAPlaylistWhoseItemsAreHiddenStillWorks() async {
        let hidden = MockFixtures.playlists.first { !$0.canReadItems }!
        await coordinator.play(playlist: hidden)
        #expect(coordinator.lastError == nil)
        #expect(coordinator.snapshot.context?.uri == hidden.uri)
    }

    @Test func transferringToARestrictedDeviceFailsAndRollsBack() async {
        await coordinator.refresh()
        let restricted = MockFixtures.devices.first(where: \.isRestricted)!
        await coordinator.transfer(to: restricted)
        #expect(coordinator.lastError == .deviceRestricted)
        #expect(coordinator.snapshot.device?.id == "dev-mac")
    }

    @Test func simulatedClockRollsOverAtTrackEnd() async {
        await coordinator.refresh()
        let first = coordinator.snapshot.track!
        clock.advance(by: first.duration)
        await services.spotify.tick()
        await coordinator.refresh()
        #expect(coordinator.snapshot.track != first)
    }

    @Test func spotifyQuittingSurfacesAsIdle() async {
        await services.spotify.simulateQuit()
        await coordinator.refresh()
        #expect(coordinator.snapshot.track == nil)
        await coordinator.next()
        #expect(coordinator.lastError == .spotifyNotRunning)
    }
}

@MainActor
struct LibraryStoreTests {
    let library = LibraryStore(api: MockServices(spotify: MockSpotify(latency: .zero)).api)

    @Test func loadsEveryPlaylistAcrossPages() async {
        await library.loadPlaylists()
        #expect(library.playlists.value?.count == 12)
    }

    @Test func unreadablePlaylistReportsItemsUnavailable() async {
        let hidden = MockFixtures.playlists.first { !$0.canReadItems }!
        await library.loadItems(for: hidden)
        #expect(library.items(for: hidden) == .failed(.playlistItemsUnavailable))
    }

    @Test func readablePlaylistLoadsItems() async {
        let playlist = MockFixtures.playlists[0]
        await library.loadItems(for: playlist)
        #expect(library.items(for: playlist).value?.count == playlist.itemCount)
    }

    @Test func pinsReorderAndRecentsAreBounded() {
        let playlists = MockFixtures.playlists
        library.pin(playlists[0])
        library.pin(playlists[1])
        library.pin(playlists[0])
        library.movePinned(fromOffsets: [1], toOffset: 0)
        #expect(library.pinnedPlaylists.map(\.id) == [playlists[1].id, playlists[0].id])
        playlists.forEach(library.recordRecent)
        #expect(library.recentPlaylists.count == LibraryStore.recentLimit)
        #expect(library.recentPlaylists.first == playlists.last)
    }

    @Test func searchMatchesFixturesAndCapsResults() async {
        await library.search("night")
        let results = library.searchResults.value
        #expect(results?.playlists.contains { $0.name == "Night Drive" } == true)
        #expect((results?.tracks.count ?? 0) <= 10)
        await library.search("   ")
        #expect(library.searchResults == .idle)
    }

    @Test func devicesIncludeARestrictedOne() async {
        await library.loadDevices()
        #expect(library.devices.value?.contains(where: \.isRestricted) == true)
    }
}

@MainActor
struct AccountStoreTests {
    @Test func restoredSessionLoadsTheProfile() async throws {
        let services = MockServices(spotify: MockSpotify(latency: .zero), authorizer: MockAuthorizer(latency: .zero))
        let account = AccountStore(authorizer: services.authorizer, api: services.api, localPlayer: services.localPlayer)
        account.start()
        for _ in 0..<100 where account.profile == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(account.authState == .signedIn)
        #expect(account.profile == MockFixtures.user)
        #expect(account.automationPermission == .granted)
    }

    @Test func signOutClearsTheProfile() async throws {
        let services = MockServices(spotify: MockSpotify(latency: .zero), authorizer: MockAuthorizer(latency: .zero))
        let account = AccountStore(authorizer: services.authorizer, api: services.api, localPlayer: services.localPlayer)
        account.start()
        for _ in 0..<100 where account.authState != .signedIn {
            try await Task.sleep(for: .milliseconds(10))
        }
        await account.signOut()
        for _ in 0..<100 where account.authState != .signedOut {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(account.authState == .signedOut)
        #expect(account.profile == nil)
    }
}
