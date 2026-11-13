import Foundation
import Observation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

// Clicking the song at index i of the queue sends "next" i + 1 times as one operation.
@MainActor
struct SkipAheadTests {
    let rig = Rig()
    var coordinator: PlaybackCoordinator { rig.coordinator }

    private func upcoming() async throws -> [Track] {
        try await rig.services.api.queue().upcoming
    }

    // Steps the manual clock while the operation waits on a Web API read or a timeout, as real time would.
    private func waitingOut(_ operation: @escaping @MainActor () async -> SkipAheadResult) async -> SkipAheadResult {
        let task = Task { await operation() }
        for _ in 0..<16 {
            rig.clock.advance(by: 0.5)
            await settle()
        }
        return await task.value
    }

    private func startLocal() async {
        coordinator.start()
        #expect(await eventually { coordinator.snapshot.context != nil })
        await settle()
    }

    @Test func onThisMacItSendsOneNextTrackPerSongAndLandsOnSpotifysNotification() async throws {
        await startLocal()
        let target = try await upcoming()[4]
        let reads = await rig.spotify.stateReads
        let requests = await rig.spotify.webRequests.count

        let result = await coordinator.skipAhead(by: 5, to: target.uri)

        #expect(result == .landed)
        #expect(Array(await rig.spotify.localCommands.suffix(5)) == Array(repeating: "next track", count: 5))
        #expect(await rig.localCommands("next track") == 5)
        #expect(await rig.webRequests("skipToNext") == 0)
        // The notification for the last song confirms it, so no state read is needed.
        #expect(await rig.spotify.stateReads == reads)
        #expect(coordinator.snapshot.track?.uri == target.uri)
        #expect(coordinator.lastError == nil)
        #expect(coordinator.pendingIntents.isEmpty)

        // Nothing for the four songs passed over: one saved-state check, then one read for context and device.
        await settle()
        #expect(Array(await rig.spotify.webRequests.dropFirst(requests)) == ["libraryContains"])
        rig.clock.advance(by: 1)
        #expect(await eventually { await rig.spotify.webRequests.count == requests + 2 })
        #expect(Array(await rig.spotify.webRequests.dropFirst(requests)) == ["libraryContains", "playbackState"])
    }

    @Test func withoutANotificationItReadsTheStateOnce() async throws {
        await coordinator.refresh()
        let target = try await upcoming()[2]
        let reads = await rig.spotify.stateReads
        let coordinator = coordinator

        let result = await waitingOut { await coordinator.skipAhead(by: 3, to: target.uri) }

        #expect(result == .landed)
        #expect(await rig.localCommands("next track") == 3)
        #expect(await rig.spotify.stateReads == reads + 1)
        #expect(coordinator.snapshot.track?.uri == target.uri)
    }

    @Test func onAnotherDeviceItSendsOneSkipPerSongAndConfirmsWithOneRead() async throws {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        await coordinator.refresh()
        #expect(coordinator.authority == .webAPI)
        let target = try await upcoming()[4]
        let reads = await rig.webRequests("playbackState")
        let coordinator = coordinator

        let result = await waitingOut { await coordinator.skipAhead(by: 5, to: target.uri) }

        #expect(result == .landed)
        #expect(await rig.webRequests("skipToNext") == 5)
        #expect(await rig.localCommands("next track") == 0)
        #expect(await rig.webRequests("playbackState") == reads + 1)
        #expect(coordinator.snapshot.track?.uri == target.uri)
        #expect(coordinator.pendingIntents.isEmpty)
    }

    @Test func theSongsPassedOverNeverReachTheSnapshotOrTheWebAPI() async throws {
        await startLocal()
        let original = coordinator.snapshot.track
        let queue = try await upcoming()
        let requests = await rig.spotify.webRequests.count
        await rig.spotify.holdCommands(afterLetting: 2)
        let coordinator = coordinator
        let skip = Task { await coordinator.skipAhead(by: 4, to: queue[3].uri) }

        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(await rig.spotify.currentLocalState()?.track?.uri == queue[1].uri)
        await settle()
        #expect(coordinator.snapshot.track == original)
        #expect(coordinator.pendingIntents == [.playTrack(queue[3].uri)])
        #expect(await rig.spotify.webRequests.count == requests)

        await rig.spotify.releaseHeld()
        #expect(await skip.value == .landed)
        #expect(coordinator.snapshot.track?.uri == queue[3].uri)
    }

    @Test func aFailureOnThisMacStopsTheSkipsAndIsReported() async throws {
        await coordinator.refresh()
        let queue = try await upcoming()
        await rig.spotify.failLocalCommands(with: .unexpected(detail: "AppleScript error"), afterLetting: 2)

        let result = await coordinator.skipAhead(by: 5, to: queue[4].uri)

        #expect(result == .failed(.unexpected(detail: "AppleScript error")))
        #expect(coordinator.lastError == .unexpected(detail: "AppleScript error"))
        // The third was refused; the remaining two were never sent, and none went to the Web API instead.
        #expect(await rig.localCommands("next track") == 3)
        #expect(await rig.webRequests("skipToNext") == 0)
        #expect(coordinator.snapshot.track?.uri == queue[1].uri)
        #expect(coordinator.pendingIntents.isEmpty)
    }

    @Test func aRateLimitOnTheWebAPIStopsTheSkipsAndPausesIt() async throws {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        await coordinator.refresh()
        let queue = try await upcoming()
        await rig.spotify.failWebRequest("skipToNext", with: .rateLimited(retryAfter: 30), afterLetting: 2)
        let coordinator = coordinator

        let result = await waitingOut { await coordinator.skipAhead(by: 5, to: queue[4].uri) }

        #expect(result == .failed(.rateLimited(retryAfter: 30)))
        #expect(coordinator.lastError == .rateLimited(retryAfter: 30))
        #expect(await rig.webRequests("skipToNext") == 3)
        #expect(await rig.localCommands("next track") == 0)
        #expect(coordinator.webAPIPausedUntil != nil)
        #expect(coordinator.pendingIntents.isEmpty)
    }

    @Test func aSecondClickWhileSkippingIsIgnored() async throws {
        await startLocal()
        let queue = try await upcoming()
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let first = Task { await coordinator.skipAhead(by: 3, to: queue[2].uri) }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(coordinator.pendingIntents.contains(.playTrack(queue[2].uri)))

        #expect(await coordinator.skipAhead(by: 2, to: queue[1].uri) == .ignored)
        #expect(!coordinator.pendingIntents.contains(.playTrack(queue[1].uri)))

        await rig.spotify.releaseHeld()
        #expect(await first.value == .landed)
        #expect(await rig.localCommands("next track") == 3)
        #expect(coordinator.snapshot.track?.uri == queue[2].uri)
        #expect(coordinator.pendingIntents.isEmpty)

        // Once it has finished, the next click is taken.
        #expect(await coordinator.skipAhead(by: 1, to: try await upcoming()[0].uri) == .landed)
    }

    @Test func theCountIsClamped() async throws {
        await coordinator.refresh()
        let coordinator = coordinator
        let target = try await upcoming()[0].uri
        _ = await waitingOut { await coordinator.skipAhead(by: 500, to: target) }
        #expect(await rig.localCommands("next track") == PlaybackCoordinator.Timing().skipAheadLimit)
        _ = await waitingOut { await coordinator.skipAhead(by: 0, to: target) }
        #expect(await rig.localCommands("next track") == PlaybackCoordinator.Timing().skipAheadLimit + 1)
    }

    // What the queue drawer does: it reloads, unforced, whenever the current song changes.
    private func emulateQueueDrawer(_ stores: OrbitStores, seen: @escaping @MainActor (Track?) -> Void) -> Task<Void, Never> {
        Task {
            for await track in Observations({ stores.playback.snapshot.track }) {
                seen(track)
                await stores.library.loadQueue()
            }
        }
    }

    @Test func theQueueIsReloadedOnceAfterAFiveSongSkip() async throws {
        let stores = rig.stores()
        stores.start()
        #expect(await eventually { stores.account.authState.isSignedIn && stores.playback.snapshot.context != nil })
        await stores.library.loadQueue()
        let queue = try #require(stores.library.queue.value?.upcoming)
        let original = stores.playback.snapshot.track
        var seen: [Track?] = []
        let drawer = emulateQueueDrawer(stores) { seen.append($0) }
        defer { drawer.cancel() }
        await settle()
        // Past the cache lifetime, so any reload the drawer starts for a song passed over would be a request.
        rig.clock.advance(by: LibraryStore.Timing().queueLifetime + 1)
        await settle()
        let reloads = await rig.webRequests("queue")

        #expect(await stores.playback.skipAhead(by: 5, to: queue[4].uri) == .landed)
        await settle()

        #expect(await rig.webRequests("queue") == reloads + 1)
        #expect(stores.library.queue.value?.current?.uri == queue[4].uri)
        #expect(stores.library.queue.value?.upcoming.first?.uri == queue[5].uri)
        #expect(seen.map { $0?.uri } == [original?.uri, queue[4].uri])
    }

    @Test func aStaleQueueLandsElsewhereSaysSoAndReloads() async throws {
        let stores = rig.stores()
        stores.start()
        #expect(await eventually { stores.account.authState.isSignedIn && stores.playback.snapshot.context != nil })
        await stores.library.loadQueue()
        let shown = try #require(stores.library.queue.value?.upcoming)
        // Something else was queued after the drawer loaded, so the third song is no longer three skips away.
        let added = try #require(MockFixtures.track(id: "al-linen-1"))
        try await rig.services.api.addToQueue(added.uri, deviceID: nil)
        let reloads = await rig.webRequests("queue")
        let playback = stores.playback

        let result = await waitingOut { await playback.skipAhead(by: 3, to: shown[2].uri) }

        #expect(result == .failed(.playbackNotConfirmed))
        #expect(playback.lastError == .playbackNotConfirmed)
        #expect(playback.snapshot.track?.uri == added.uri)
        #expect(playback.pendingIntents.isEmpty)
        #expect(await rig.webRequests("queue") == reloads + 1)
        #expect(stores.library.queue.value?.current?.uri == added.uri)
        #expect(await rig.localCommands("next track") == 3)
    }

    @Test func theDemoQueueAdvancesSongBySong() async throws {
        await startLocal()
        let queue = try await upcoming()
        #expect(await coordinator.skipAhead(by: 3, to: queue[2].uri) == .landed)
        let after = try await rig.services.api.queue()
        #expect(after.current?.uri == queue[2].uri)
        #expect(after.upcoming.prefix(2).map(\.uri) == queue[3...4].map(\.uri))
    }
}
