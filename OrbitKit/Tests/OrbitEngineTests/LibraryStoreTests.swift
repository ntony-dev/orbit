import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

@MainActor
struct LibraryStoreTests {
    let rig = Rig()
    let library: LibraryStore

    init() {
        library = LibraryStore(api: rig.services.api, clock: rig.engineClock)
    }

    private func temporaryShelf() -> LibraryShelfFile {
        LibraryShelfFile(url: FileManager.default.temporaryDirectory
            .appending(path: "OrbitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Library.json"))
    }

    @Test func loadsEveryPlaylistAcrossPages() async {
        await library.loadPlaylists()
        #expect(library.playlists.value?.count == 12)
    }

    // The real client drops null and local entries and reports where the next page starts.
    @Test func pagesFollowTheReportedNextOffset() async {
        let dropped = [MockFixtures.playlists[1].id, MockFixtures.playlists[6].id]
        let droppedTrack = MockFixtures.savedTrackIDs[2]
        await rig.spotify.pageLikeTheWebAPI(size: 5, dropping: Set(dropped + [droppedTrack]))
        await library.loadPlaylists()
        await library.loadSavedTracks()
        let expected = MockFixtures.playlists.map(\.id).filter { !dropped.contains($0) }
        #expect(library.playlists.value?.map(\.id) == expected)
        #expect(library.savedTracks.value?.map(\.id) == MockFixtures.savedTrackIDs.filter { $0 != droppedTrack })
        #expect(await rig.webRequests("playlists") == 3)
    }

    @Test func reopeningWithinTheCacheLifetimeMakesNoRequest() async {
        await library.loadPlaylists()
        await library.loadPlaylists()
        #expect(await rig.webRequests("playlists") == 1)
        await library.loadPlaylists(force: true)
        #expect(await rig.webRequests("playlists") == 2)
        rig.clock.advance(by: LibraryStore.Timing().playlistsLifetime + 1)
        await library.loadPlaylists()
        #expect(await rig.webRequests("playlists") == 3)
    }

    @Test func concurrentViewsShareOneRequest() async {
        await rig.spotify.holdReads()
        let library = library
        let loads = (0..<3).map { _ in Task { await library.loadDevices() } }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        await rig.spotify.releaseHeld()
        for load in loads { await load.value }
        #expect(await rig.webRequests("devices") == 1)
        #expect(library.devices.value?.count == MockFixtures.devices.count)
    }

    @Test func aFailedLoadEndsFailedNotLoading() async {
        await rig.spotify.failWebAPI(with: .network(detail: "offline"))
        await library.loadPlaylists()
        await library.loadSavedTracks()
        await library.loadQueue()
        await library.loadDevices()
        #expect(library.playlists == .failed(.network(detail: "offline")))
        #expect(library.savedTracks.error != nil)
        #expect(library.queue.error != nil)
        #expect(library.devices.error != nil)
    }

    @Test func aFailedRefreshKeepsTheCachedValue() async {
        await library.loadPlaylists()
        await rig.spotify.failWebAPI(with: .rateLimited(retryAfter: 5))
        await library.loadPlaylists(force: true)
        #expect(library.playlists.value?.count == 12)
    }

    @Test func unreadablePlaylistReportsItemsUnavailableWithoutARequest() async {
        let hidden = MockFixtures.playlists.first { !$0.canReadItems }!
        await library.loadItems(for: hidden)
        #expect(library.items(for: hidden) == .failed(.playlistItemsUnavailable))
        #expect(await rig.webRequests("playlistItems") == 0)
    }

    @Test func readablePlaylistLoadsItemsOnce() async {
        let playlist = MockFixtures.playlists[0]
        await library.loadItems(for: playlist)
        await library.loadItems(for: playlist)
        #expect(library.items(for: playlist).value?.count == playlist.itemCount)
        #expect(await rig.webRequests("playlistItems") == 1)
    }

    @Test func likedSongsItemsAreTheSavedTracks() async throws {
        library.setUser(MockFixtures.user)
        let liked = try #require(library.likedSongs)
        #expect(liked.uri.kind == .collection)
        await library.loadItems(for: liked)
        #expect(library.items(for: liked).value?.count == MockFixtures.savedTrackIDs.count)
        #expect(library.likedSongs?.itemCount == MockFixtures.savedTrackIDs.count)
    }

    @Test func searchIsDebouncedAndOnlyTheLastQueryIsSent() async {
        for query in ["n", "ni", "nig", "night"] {
            library.updateSearch(query)
            await Task.yield()
        }
        #expect(library.searchResults == .loading)
        #expect(await eventually { rig.clock.pendingSleepers == 1 })
        rig.clock.advance(by: 0.3)
        #expect(await eventually { library.searchResults.value != nil })
        #expect(await rig.webRequests("search") == 1)
        #expect(library.searchResults.value?.playlists.contains { $0.name == "Night Drive" } == true)

        library.updateSearch("night")
        #expect(library.searchResults.value != nil)
        #expect(await rig.webRequests("search") == 1)
        library.updateSearch("   ")
        #expect(library.searchResults == .idle)
    }

    // Refining a search or refreshing any list keeps what is on screen until the new result or an error lands.
    @Test func reloadsKeepTheirValueVisibleWhileLoading() async {
        await library.search("night")
        let night = library.searchResults.value
        #expect(night != nil)
        await library.loadPlaylists()
        await library.loadSavedTracks()
        await library.loadDevices()
        await library.loadQueue()
        await library.loadItems(for: MockFixtures.playlists[0])

        await rig.spotify.holdReads()
        let library = library
        library.updateSearch("jazz")
        #expect(library.searchResults.value == night)
        #expect(library.isSearching)
        let reloads = [
            Task { await library.loadPlaylists(force: true) },
            Task { await library.loadSavedTracks(force: true) },
            Task { await library.loadDevices(force: true) },
            Task { await library.loadQueue(force: true) },
            Task { await library.loadItems(for: MockFixtures.playlists[0], force: true) },
        ]
        #expect(await eventually { rig.clock.pendingSleepers == 1 })
        rig.clock.advance(by: 1)
        #expect(await eventually { await rig.spotify.heldRequestCount == 6 })
        #expect(library.searchResults.value == night)
        #expect(library.playlists.value != nil)
        #expect(library.savedTracks.value != nil)
        #expect(library.devices.value != nil)
        #expect(library.queue.value != nil)
        #expect(library.items(for: MockFixtures.playlists[0]).value != nil)

        await rig.spotify.releaseHeld()
        for reload in reloads { await reload.value }
        #expect(await eventually { !library.isSearching })
        #expect(library.searchResults.value?.playlists.contains { $0.name == "Late Night Jazz" } == true)
        #expect(library.searchResults.value != night)
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

    @Test func pinsAndRecentsSurviveARestart() async throws {
        let file = temporaryShelf()
        let first = LibraryStore(api: rig.services.api, shelfFile: file, clock: rig.engineClock)
        await first.restoreShelf()
        first.pin(MockFixtures.playlists[2])
        first.pin(MockFixtures.playlists[5])
        first.recordRecent(MockFixtures.playlists[7])
        #expect(await eventually { await file.load()?.recents.count == 1 })

        let second = LibraryStore(api: rig.services.api, shelfFile: file, clock: rig.engineClock)
        await second.restoreShelf()
        #expect(second.pinnedPlaylists.map(\.id) == [MockFixtures.playlists[2].id, MockFixtures.playlists[5].id])
        #expect(second.recentPlaylists.map(\.id) == [MockFixtures.playlists[7].id])
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
    }

    @Test func aDeletedPlaylistStaysPinnedButIsFlaggedMissing() async {
        let doomed = MockFixtures.playlists[3]
        library.pin(doomed)
        library.recordRecent(doomed)
        await rig.spotify.removePlaylist(id: doomed.id)
        await library.loadPlaylists()
        #expect(library.pinnedPlaylists.contains { $0.id == doomed.id })
        #expect(library.recentPlaylists.contains { $0.id == doomed.id })
        #expect(library.missingPlaylistIDs == [doomed.id])
    }

    @Test func openingADeletedPlaylistFlagsItMissing() async {
        let doomed = MockFixtures.playlists[3]
        library.pin(doomed)
        await rig.spotify.removePlaylist(id: doomed.id)
        await library.loadItems(for: doomed)
        #expect(library.items(for: doomed) == .failed(.notFound))
        #expect(library.missingPlaylistIDs == [doomed.id])
        #expect(library.isPinned(doomed))
    }

    @Test func aSavedDeviceThatNoLongerExistsIsReportedMissing() async {
        let gone = DeviceReference(id: "dev-old", name: "Old Speaker")
        library.preferredDevice = { gone }
        #expect(library.preferredDeviceStatus == .unverified(gone))
        await library.loadDevices()
        #expect(library.preferredDeviceStatus == .missing(gone))

        let renamedID = DeviceReference(id: "stale-id", name: "Kitchen Speaker")
        library.preferredDevice = { renamedID }
        guard case .available(let device) = library.preferredDeviceStatus else {
            Issue.record("Expected the device to be matched by name")
            return
        }
        #expect(device.id == "dev-kitchen")
    }

    @Test func addingToTheQueueRefreshesIt() async {
        await library.loadQueue()
        let track = MockFixtures.tracks.last!
        #expect(await library.addToQueue(track))
        #expect(library.queue.value?.upcoming.contains(track) == true)
    }

    @Test func signingOutDropsAccountDataButKeepsPins() async {
        await library.loadPlaylists()
        library.pin(MockFixtures.playlists[0])
        library.reset()
        #expect(library.playlists == .idle)
        #expect(library.pinnedPlaylists.count == 1)
        await library.loadPlaylists()
        #expect(await rig.webRequests("playlists") == 2)
    }

    // Signing out mid-load must not let the old account's data land afterwards.
    @Test func loadsInFlightAtSignOutAreDiscarded() async {
        library.updateSearch("night")
        await rig.spotify.holdReads()
        let library = library
        let loads = [
            Task { await library.loadPlaylists() },
            Task { await library.loadSavedTracks() },
            Task { await library.loadDevices() },
            Task { await library.loadQueue() },
            Task { await library.loadItems(for: MockFixtures.playlists[0]) },
        ]
        #expect(await eventually { rig.clock.pendingSleepers == 1 })
        rig.clock.advance(by: 1)
        #expect(await eventually { await rig.spotify.heldRequestCount == 6 })
        library.reset()
        await rig.spotify.releaseHeld()
        for load in loads { await load.value }
        await settle()
        #expect(library.playlists == .idle)
        #expect(library.savedTracks == .idle)
        #expect(library.devices == .idle)
        #expect(library.queue == .idle)
        #expect(library.playlistItems.isEmpty)
        #expect(library.searchResults == .idle)
        await library.loadPlaylists()
        #expect(await rig.webRequests("playlists") == 2)
    }
}
