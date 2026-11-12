import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

@MainActor
struct PlaybackCoordinatorTests {
    let rig = Rig()
    var coordinator: PlaybackCoordinator { rig.coordinator }

    @Test func localAppIsAuthoritativeAndTheWebAPIAddsWhatAppleScriptCannot() async {
        await coordinator.refresh()
        let snapshot = coordinator.snapshot
        #expect(coordinator.authority == .local)
        #expect(snapshot.track?.name == "Afterglow Avenue")
        #expect(snapshot.isPlaying)
        #expect(snapshot.context?.uri == MockFixtures.startingPlaylist.uri)
        #expect(snapshot.device?.id == MockFixtures.localDevice.id)
        #expect(snapshot.allows(.skipNext))
        #expect(snapshot.allows(.toggleRepeatTrack))
        #expect(snapshot.allows(.transfer))
        #expect(coordinator.isCurrentTrackSaved == true)
    }

    @Test func progressIsInterpolatedFromTheSampleNotPolled() async {
        await coordinator.refresh()
        let requests = await rig.webRequests("playbackState")
        let start = coordinator.snapshot.position(at: rig.clock.now())
        #expect(abs(coordinator.snapshot.position(at: rig.clock.now().addingTimeInterval(10)) - start - 10) < 0.001)
        #expect(await rig.webRequests("playbackState") == requests)
    }

    @Test func togglePlayPauseRoundTrips() async {
        await coordinator.refresh()
        await coordinator.togglePlayPause()
        #expect(!coordinator.snapshot.isPlaying)
        await coordinator.togglePlayPause()
        #expect(coordinator.snapshot.isPlaying)
        #expect(coordinator.pendingIntents.isEmpty)
        #expect(await rig.localCommands("pause") == 1)
        #expect(await rig.webRequests("pause") == 0)
    }

    @Test func nextShowsTheTrackSpotifyMovedTo() async {
        await coordinator.refresh()
        await coordinator.next()
        #expect(coordinator.snapshot.track?.id == MockFixtures.queuedTrackIDs[0])
    }

    @Test func rapidSkipsAreSerializedAndEachOneLands() async {
        await coordinator.refresh()
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let skips = (0..<3).map { _ in Task { await coordinator.next() } }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(coordinator.pendingIntents.contains(.next))
        await rig.spotify.releaseHeld()
        for skip in skips { await skip.value }
        #expect(await rig.localCommands("next track") == 3)
        #expect(coordinator.snapshot.track?.id == MockFixtures.playlistTracks[MockFixtures.startingPlaylist.id]?[1].id)
        #expect(coordinator.pendingIntents.isEmpty)
    }

    @Test func aStaleNotificationNeverUndoesASeek() async throws {
        coordinator.start()
        await coordinator.refresh()
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let seek = Task { await coordinator.seek(to: 100) }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(coordinator.snapshot.position(at: rig.clock.now()) == 100)

        var stale = try #require(await rig.spotify.currentLocalState())
        stale.position = 30
        await rig.spotify.emitLocalState(stale)
        await settle()
        #expect(coordinator.snapshot.position(at: rig.clock.now()) == 100)

        await rig.spotify.releaseHeld()
        await seek.value
        await rig.spotify.emitLocalState(stale)
        await settle()
        #expect(coordinator.snapshot.position(at: rig.clock.now()) == 100)

        // Once the grace period ends the coordinator reads back the real state rather than trusting the stale one.
        rig.clock.advance(by: 2)
        #expect(await eventually { abs(coordinator.snapshot.position(at: rig.clock.now()) - 102) < 0.5 })
    }

    // The pause's optimistic position is still in its grace period when the seek is issued; the newer intent wins.
    @Test func aSeekRightAfterPausingShowsTheSeekTarget() async {
        await coordinator.refresh()
        await coordinator.togglePlayPause()
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let seek = Task { await coordinator.seek(to: 100) }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(coordinator.snapshot.position(at: rig.clock.now()) == 100)
        await rig.spotify.releaseHeld()
        await seek.value
        #expect(coordinator.snapshot.position(at: rig.clock.now()) == 100)
    }

    @Test func aSeekDuringASkipLandsOnTheNewTrack() async {
        await coordinator.refresh()
        let first = coordinator.snapshot.track?.id
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let skip = Task { await coordinator.next() }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        let seek = Task { await coordinator.seek(to: 42) }
        await rig.spotify.releaseHeld()
        await skip.value
        await seek.value
        #expect(coordinator.snapshot.track?.id != first)
        let mock = await rig.spotify.currentLocalState()
        #expect(mock?.track?.id == coordinator.snapshot.track?.id)
        #expect(abs((mock?.position ?? 0) - 42) < 0.5)
    }

    @Test func coalescesRapidVolumeChangesToTheLatestValue() async {
        await coordinator.refresh()
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let changes = [10, 20, 30].map { value in Task { await coordinator.setVolume(value) } }
        #expect(await eventually { coordinator.snapshot.volume == 30 })
        await rig.spotify.releaseHeld()
        for change in changes { await change.value }
        #expect(coordinator.snapshot.volume == 30)
        #expect(await rig.localCommands("set sound volume") <= 2)
        #expect(await rig.spotify.currentLocalState()?.volume == 30)
    }

    @Test func aFailedCommandRollsBackAndSurfacesTheError() async {
        await coordinator.refresh()
        await rig.spotify.failLocalCommands(with: .unexpected(detail: "AppleEvent timed out"))
        await rig.spotify.failWebAPI(with: .network(detail: "offline"))
        await coordinator.togglePlayPause()
        #expect(coordinator.snapshot.isPlaying)
        #expect(coordinator.lastError == .network(detail: "offline"))
        #expect(coordinator.pendingIntents.isEmpty)
    }

    @Test func automationDeniedFallsBackToTheWebAPI() async {
        await rig.spotify.setAutomationPermission(.denied)
        await coordinator.refresh()
        #expect(coordinator.snapshot.allows(.pause))
        await coordinator.togglePlayPause()
        #expect(coordinator.lastError == nil)
        #expect(!coordinator.snapshot.isPlaying)
        #expect(await rig.webRequests("pause") == 1)
        #expect(await rig.spotify.localCommands.isEmpty)
    }

    // A fresh install: nothing is observed until the first command, which is what asks for Automation.
    @Test func theFirstLocalCommandAsksForAutomation() async {
        await rig.spotify.setAutomationPermission(.notDetermined)
        coordinator.setWebAPIAvailable(false)
        await coordinator.refresh()
        #expect(coordinator.snapshot.track == nil)
        await coordinator.togglePlayPause()
        #expect(coordinator.lastError == nil)
        #expect(await rig.localCommands("play") == 1)
        #expect(coordinator.snapshot.track != nil)
    }

    @Test func localControlsKeepWorkingWhileTheWebAPIIsDown() async {
        await coordinator.refresh()
        await rig.spotify.failWebAPI(with: .network(detail: "offline"))
        await coordinator.next()
        #expect(coordinator.lastError == nil)
        #expect(coordinator.snapshot.track?.id == MockFixtures.queuedTrackIDs[0])
    }

    @Test func signedOutStillControlsTheLocalAppButOffersNoWebOnlyActions() async {
        coordinator.setWebAPIAvailable(false)
        await coordinator.refresh()
        #expect(await rig.spotify.webRequests.isEmpty)
        #expect(coordinator.authority == .local)
        #expect(coordinator.snapshot.allows(.skipNext))
        #expect(!coordinator.snapshot.allows(.transfer))
        #expect(!coordinator.snapshot.allows(.toggleRepeatTrack))
        await coordinator.next()
        #expect(coordinator.lastError == nil)
        #expect(await rig.spotify.webRequests.isEmpty)
    }

    @Test func rateLimitingPausesTheWebAPIForTheRetryInterval() async {
        await coordinator.refresh()
        await rig.spotify.failWebAPI(with: .rateLimited(retryAfter: 30))
        let before = await rig.webRequests("playbackState")
        await coordinator.refresh()
        #expect(coordinator.webAPIPausedUntil == rig.clock.now().addingTimeInterval(30))
        await coordinator.refresh()
        await coordinator.refresh()
        #expect(await rig.webRequests("playbackState") == before + 1)

        await coordinator.next()
        #expect(coordinator.lastError == nil)

        await coordinator.setRepeat(.track)
        #expect(coordinator.lastError == .rateLimited(retryAfter: 30))
        #expect(await rig.webRequests("setRepeat") == 0)

        await rig.spotify.failWebAPI(with: nil)
        rig.clock.advance(by: 31)
        await coordinator.refresh()
        #expect(await rig.webRequests("playbackState") > before + 1)
        #expect(coordinator.syncError == nil)
        #expect(coordinator.webAPIPausedUntil == nil)
    }

    @Test func signingOutClearsWebSyncFailures() async {
        await coordinator.refresh()
        await rig.spotify.failWebAPI(with: .rateLimited(retryAfter: 30))
        await coordinator.refresh()
        #expect(coordinator.syncError != nil)
        coordinator.setWebAPIAvailable(false)
        #expect(coordinator.syncError == nil)
        #expect(coordinator.webAPIPausedUntil == nil)
    }

    // A 401 that survives the client's refresh, or a missing scope, fails one request; only the account store
    // decides that the session is gone, so the next sync must still go out.
    @Test func anAuthErrorFromOneRequestDoesNotDisableTheWebAPI() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        await coordinator.refresh()
        await rig.spotify.failWebAPI(with: .authExpired)
        await coordinator.refresh()
        await rig.spotify.failWebAPI(with: nil)
        let before = await rig.webRequests("playbackState")
        await coordinator.refresh()
        #expect(await rig.webRequests("playbackState") == before + 1)
        #expect(coordinator.authority == .webAPI)
        #expect(coordinator.snapshot.device?.id == "dev-kitchen")
    }

    @Test func quotaExhaustionWithoutRetryAfterUsesTheDefaultBackoff() async {
        await coordinator.refresh()
        await rig.spotify.failWebAPI(with: .quotaExceeded(retryAfter: nil))
        await coordinator.refresh()
        #expect(coordinator.webAPIPausedUntil == rig.clock.now().addingTimeInterval(PlaybackCoordinator.Timing().defaultBackoff))
        #expect(coordinator.syncError == .quotaExceeded(retryAfter: nil))
    }

    @Test func repeatOneGoesThroughTheWebAPIAndSurvivesLocalReads() async {
        await coordinator.refresh()
        await coordinator.setRepeat(.track)
        #expect(await rig.webRequests("setRepeat") == 1)
        #expect(await rig.localCommands("set repeating") == 0)
        #expect(coordinator.snapshot.repeatMode == .track)
        await coordinator.refresh()
        #expect(coordinator.snapshot.repeatMode == .track)

        coordinator.setWebAPIAvailable(false)
        #expect(!coordinator.snapshot.allows(.toggleRepeatTrack))
        await coordinator.cycleRepeat()
        #expect(coordinator.snapshot.repeatMode == .off)
        #expect(await rig.localCommands("set repeating") == 1)
    }

    @Test func playbackOnAnotherDeviceMakesTheWebAPIAuthoritative() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        await coordinator.refresh()
        #expect(coordinator.authority == .webAPI)
        #expect(coordinator.snapshot.device?.id == "dev-kitchen")
        await coordinator.next()
        #expect(await rig.webRequests("skipToNext") == 1)
        #expect(await rig.localCommands("next track") == 0)
    }

    @Test func aRestrictedDeviceOffersNoActions() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-tv")
        await coordinator.refresh()
        #expect(coordinator.authority == .webAPI)
        #expect(coordinator.snapshot.availableActions.isEmpty)
    }

    @Test func aDeviceWithoutVolumeControlHidesVolume() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-phone")
        await coordinator.refresh()
        #expect(coordinator.snapshot.allows(.skipNext))
        #expect(!coordinator.snapshot.allows(.setVolume))
    }

    @Test func transferringToARestrictedDeviceFailsAndRollsBack() async {
        await coordinator.refresh()
        let restricted = MockFixtures.devices.first(where: \.isRestricted)!
        await coordinator.transfer(to: restricted)
        #expect(coordinator.lastError == .deviceRestricted)
        #expect(coordinator.snapshot.device?.id == MockFixtures.localDevice.id)
    }

    @Test func spotifyQuittingSurfacesAsIdle() async {
        await rig.spotify.simulateQuit()
        await coordinator.refresh()
        #expect(coordinator.snapshot.track == nil)
        #expect(coordinator.authority == nil)
        await coordinator.next()
        #expect(coordinator.lastError == .spotifyNotRunning)
    }

    @Test func remotePlaybackStaysVisibleWhenTheLocalAppQuits() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-phone")
        await rig.spotify.simulateQuit()
        await coordinator.refresh()
        #expect(coordinator.authority == .webAPI)
        #expect(coordinator.snapshot.isPlaying)
        await coordinator.togglePlayPause()
        #expect(await rig.webRequests("pause") == 1)
    }

    @Test func savingTheCurrentTrackRoundTrips() async {
        await coordinator.refresh()
        await coordinator.toggleSaved()
        #expect(coordinator.isCurrentTrackSaved == false)
        #expect(await rig.webRequests("removeFromLibrary") == 1)
        await coordinator.toggleSaved()
        #expect(coordinator.isCurrentTrackSaved == true)
    }

    // While the Web API is paused the saved state cannot be looked up, but one already known still applies.
    @Test func aTrackThatComesBackKeepsItsKnownSavedState() async throws {
        coordinator.start()
        await coordinator.refresh()
        #expect(coordinator.isCurrentTrackSaved == true)
        await rig.spotify.failWebAPI(with: .rateLimited(retryAfter: 30))
        await coordinator.refresh()
        let saved = try #require(await rig.spotify.currentLocalState())
        var other = saved
        other.track = MockFixtures.track(id: MockFixtures.queuedTrackIDs[0])
        await rig.spotify.emitLocalState(other)
        #expect(await eventually { coordinator.snapshot.track?.uri == other.track?.uri })
        #expect(coordinator.isCurrentTrackSaved == nil)
        await rig.spotify.emitLocalState(saved)
        #expect(await eventually { coordinator.snapshot.track?.uri == saved.track?.uri })
        #expect(await eventually { coordinator.isCurrentTrackSaved == true })

        await rig.spotify.failWebAPI(with: nil)
        rig.clock.advance(by: 31)
        await coordinator.refresh()
        #expect(coordinator.isCurrentTrackSaved == true)
    }

    @Test func simulatedClockRollsOverAtTrackEnd() async {
        await coordinator.refresh()
        let first = coordinator.snapshot.track!
        rig.clock.advance(by: first.duration)
        await rig.spotify.tick()
        await coordinator.refresh()
        #expect(coordinator.snapshot.track != first)
    }

    @Test func hiddenNeverPollsWhileExpandedPollsRemotePlayback() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        coordinator.start()
        await coordinator.refresh()
        coordinator.setInterfaceVisibility(.hidden)
        await settle()
        let base = await rig.webRequests("playbackState")
        for _ in 0..<6 {
            rig.clock.advance(by: 20)
            await settle()
        }
        #expect(await rig.webRequests("playbackState") == base)

        coordinator.setInterfaceVisibility(.expanded)
        #expect(await eventually { await rig.webRequests("playbackState") == base + 1 })
        #expect(await eventually {
            rig.clock.advance(by: 5)
            return await rig.webRequests("playbackState") >= base + 2
        })
    }

    // The desktop app keeps posting notifications while another device plays; hidden, none of them may poll.
    @Test func localNotificationsDoNotPollWhileHidden() async throws {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        coordinator.start()
        await coordinator.refresh()
        #expect(coordinator.authority == .webAPI)
        coordinator.setInterfaceVisibility(.hidden)
        await settle()
        let base = await rig.webRequests("playbackState")
        let state = try #require(await rig.spotify.currentLocalState())
        for _ in 0..<3 {
            await rig.spotify.emitLocalState(state)
            await settle()
            rig.clock.advance(by: 2)
            await settle()
        }
        #expect(await rig.webRequests("playbackState") == base)
    }

    @Test func syncIntervalsFollowVisibilityAndAuthority() {
        #expect(PlaybackCoordinator.syncDelay(visibility: .hidden, authority: .webAPI, untilTrackEnds: 100) == nil)
        #expect(PlaybackCoordinator.syncDelay(visibility: .collapsed, authority: .local, untilTrackEnds: nil) == nil)
        #expect(PlaybackCoordinator.syncDelay(visibility: .expanded, authority: .webAPI, untilTrackEnds: 100) == .seconds(5))
        #expect(PlaybackCoordinator.syncDelay(visibility: .collapsed, authority: .webAPI, untilTrackEnds: 100) == .seconds(15))
        // A remote track about to end is checked right after it should have changed.
        #expect(PlaybackCoordinator.syncDelay(visibility: .collapsed, authority: .webAPI, untilTrackEnds: 3) == .seconds(4))
        #expect(PlaybackCoordinator.syncDelay(visibility: .expanded, authority: .local, untilTrackEnds: 3) == .seconds(30))
    }

    @Test func syncFrequencyScalesOrStopsCollapsedPolling() {
        func delay(_ visibility: InterfaceVisibility, _ frequency: SyncFrequency, untilTrackEnds: TimeInterval? = 100) -> Duration? {
            PlaybackCoordinator.syncDelay(visibility: visibility, authority: .webAPI, untilTrackEnds: untilTrackEnds, frequency: frequency)
        }
        #expect(delay(.collapsed, .reduced) == .seconds(45))
        #expect(delay(.expanded, .reduced) == .seconds(15))
        // The end of a remote track is still caught on time.
        #expect(delay(.collapsed, .reduced, untilTrackEnds: 3) == .seconds(4))
        #expect(delay(.collapsed, .whileOpen) == nil)
        #expect(delay(.expanded, .whileOpen) == .seconds(5))
        #expect(PlaybackCoordinator.syncDelay(visibility: .collapsed, authority: nil, untilTrackEnds: nil, frequency: .whileOpen) == nil)
    }

    @Test func syncingOnlyWhileOpenLeavesThePillUnpolled() async {
        await rig.spotify.simulateRemotePlayback(on: "dev-kitchen")
        coordinator.syncFrequency = .whileOpen
        coordinator.start()
        await coordinator.refresh()
        coordinator.setInterfaceVisibility(.collapsed)
        await settle()
        let base = await rig.webRequests("playbackState")
        for _ in 0..<4 {
            rig.clock.advance(by: 20)
            await settle()
        }
        #expect(await rig.webRequests("playbackState") == base)

        coordinator.syncFrequency = .standard
        #expect(await eventually {
            rig.clock.advance(by: 15)
            return await rig.webRequests("playbackState") > base
        })
    }
}
