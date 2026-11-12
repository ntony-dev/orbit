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

    @Test func onlyTheMostRecentlyShownPlaylistsKeepTheirTracks() async {
        var timing = LibraryStore.Timing()
        timing.playlistsKept = 3
        let library = LibraryStore(api: rig.services.api, clock: rig.engineClock, timing: timing)
        let readable = MockFixtures.playlists.filter(\.canReadItems)
        #expect(readable.count > 4)
        for playlist in readable.prefix(3) { await library.loadItems(for: playlist) }
        // Shown again just now, so it outlives the older two.
        #expect(library.items(for: readable[0]).value != nil)
        await library.loadItems(for: readable[3])
        await library.loadItems(for: readable[4])
        #expect(library.playlistItems.count == 3)
        #expect(library.items(for: readable[1]) == .idle)
        #expect(library.items(for: readable[2]) == .idle)

        let requests = await rig.webRequests("playlistItems")
        await library.loadItems(for: readable[0])
        await library.loadItems(for: readable[4])
        #expect(await rig.webRequests("playlistItems") == requests)
        await library.loadItems(for: readable[1])
        #expect(await rig.webRequests("playlistItems") == requests + 1)
        #expect(library.items(for: readable[1]).value != nil)
    }

    @Test func searchResultsAreBoundedAndExpiredOnesDropped() async {
        var timing = LibraryStore.Timing()
        timing.searchesKept = 2
        let library = LibraryStore(api: rig.services.api, clock: rig.engineClock, timing: timing)
        for query in ["night", "jazz", "rain"] {
            await library.search(query)
            rig.clock.advance(by: 1)
        }
        #expect(await rig.webRequests("search") == 3)
        await library.search("rain")
        await library.search("jazz")
        #expect(await rig.webRequests("search") == 3)
        await library.search("night")
        #expect(await rig.webRequests("search") == 4)

        rig.clock.advance(by: timing.searchLifetime + 1)
        await library.search("lofi")
        await library.search("night")
        #expect(await rig.webRequests("search") == 6)
    }

    // The Library shows Liked Songs' count on its row; that must not page through the whole collection.
    @Test(arguments: [0, 2_000])
    func openingTheLibraryCostsTheSameRequestsHoweverManySongsAreLiked(extra: Int) async throws {
        await rig.spotify.addSavedTracks(count: extra)
        let stores = rig.stores()
        stores.start()
        #expect(await eventually { stores.library.playlists.value != nil && stores.library.likedSongs != nil })
        await settle()
        let before = await rig.spotify.webRequests.count

        // What the Library tab's task does when it first appears.
        await stores.library.loadPlaylists()
        if stores.library.likedSongsCount == nil { await stores.library.loadLikedSongsCount() }
        await settle()

        #expect(await rig.spotify.webRequests.count - before == 1)
        #expect(await rig.webRequests("savedTracks") == 1)
        let total = await rig.spotify.savedTrackCount
        #expect(stores.library.likedSongsCount == total)
        #expect(stores.library.likedSongs?.itemCount == total)
        #expect(stores.library.savedTracks == .idle)

        // Shown again: the count is known, so nothing more is asked.
        if stores.library.likedSongsCount == nil { await stores.library.loadLikedSongsCount() }
        #expect(await rig.webRequests("savedTracks") == 1)
    }

    @Test func likedSongsTracksLoadOnlyWhenOpened() async throws {
        await rig.spotify.addSavedTracks(count: 120)
        library.setUser(MockFixtures.user)
        await library.loadLikedSongsCount()
        let liked = try #require(library.likedSongs)
        #expect(library.items(for: liked) == .idle)
        await library.loadItems(for: liked)
        let total = await rig.spotify.savedTrackCount
        #expect(library.items(for: liked).value?.count == total)
        #expect(library.likedSongsCount == total)
        #expect(await rig.webRequests("savedTracks") == 1 + (total + 49) / 50)
    }

    private static let long = Playlist(id: "pl-long", name: "Long Drive", ownerName: "Tony", itemCount: 230, canReadItems: true)

    // Rows show once the first page lands and later pages append; nothing is replaced along the way.
    @Test func aPlaylistShowsItsFirstPageWhileTheRestLoad() async {
        await rig.spotify.addPlaylist(Self.long, trackCount: 230)
        await library.loadPlaylists()
        await rig.spotify.holdReads(["playlistItems"], afterLetting: 1)
        let library = library
        let loading = Task { await library.loadItems(for: Self.long) }
        #expect(await eventually { library.items(for: Self.long).value?.count == 50 })
        #expect(library.remainingPages(for: Self.long) == .loading)
        #expect(library.knownTrackURIs(for: Self.long.uri) == nil)
        await rig.spotify.releaseHeld()
        await loading.value
        let tracks = library.items(for: Self.long).value ?? []
        #expect(tracks.count == 230)
        #expect(tracks.map(\.id) == (0..<230).map { "pl-long-\($0)" })
        #expect(library.remainingPages(for: Self.long) == nil)
        #expect(library.knownTrackURIs(for: Self.long.uri)?.count == 230)
        #expect(await rig.webRequests("playlistItems") == 5)
    }

    @Test func aFailedLaterPageKeepsTheRowsAndContinuesWhereItStopped() async {
        await rig.spotify.addPlaylist(Self.long, trackCount: 230)
        await rig.spotify.failWebRequest("playlistItems", with: .network(detail: "offline"), afterLetting: 2)
        await library.loadItems(for: Self.long)
        #expect(library.items(for: Self.long).value?.count == 100)
        #expect(library.remainingPages(for: Self.long) == .failed(.network(detail: "offline")))

        await rig.spotify.failWebRequest("playlistItems", with: nil)
        await library.loadItems(for: Self.long)
        #expect(library.items(for: Self.long).value?.count == 230)
        #expect(library.remainingPages(for: Self.long) == nil)
        #expect(await rig.webRequests("playlistItems") == 3 + 3)
    }

    // A complete list on screen is refreshed whole, so it never shrinks to one page and grows back.
    @Test func refreshingACompleteListKeepsItUntilTheNewOneHasLoaded() async {
        await rig.spotify.addPlaylist(Self.long, trackCount: 230)
        await library.loadItems(for: Self.long)
        await rig.spotify.holdReads(["playlistItems"], afterLetting: 2)
        let library = library
        let refreshing = Task { await library.loadItems(for: Self.long, force: true) }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(library.items(for: Self.long).value?.count == 230)
        #expect(library.remainingPages(for: Self.long) == nil)
        await rig.spotify.releaseHeld()
        await refreshing.value
        #expect(library.items(for: Self.long).value?.count == 230)
    }

    @Test func likedSongsAppendPagesAndKeepTheirCountSteady() async throws {
        await rig.spotify.addSavedTracks(count: 145)
        library.setUser(MockFixtures.user)
        await library.loadLikedSongsCount()
        let total = await rig.spotify.savedTrackCount
        #expect(library.likedSongsCount == total)
        let liked = try #require(library.likedSongs)
        await rig.spotify.holdReads(["savedTracks"], afterLetting: 1)
        let library = library
        let loading = Task { await library.loadItems(for: liked) }
        #expect(await eventually { library.items(for: liked).value?.count == 50 })
        #expect(library.remainingPages(for: liked) == .loading)
        #expect(library.likedSongsCount == total)
        #expect(library.knownTrackURIs(for: liked.uri) == nil)
        await rig.spotify.releaseHeld()
        await loading.value
        #expect(library.items(for: liked).value?.count == total)
        #expect(library.likedSongsCount == total)
        #expect(library.remainingPages(for: liked) == nil)
    }

    @Test func aPlaylistWhoseItemsAreHiddenStillReportsThemUnavailable() async {
        let hidden = Playlist(id: "pl-hidden-long", name: "Theirs", ownerName: "Someone", itemCount: 80, canReadItems: true)
        await rig.spotify.addPlaylist(hidden, trackCount: 80)
        await rig.spotify.failWebRequest("playlistItems", with: .playlistItemsUnavailable)
        await library.loadItems(for: hidden)
        #expect(library.items(for: hidden) == .failed(.playlistItemsUnavailable))
        #expect(library.remainingPages(for: hidden) == nil)
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
