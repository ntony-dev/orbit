import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

// AppleScript reports repeat as on or off; only the Web API can tell repeat-one from repeat-context. What Orbit
// shows must still converge to what Spotify does, and each click must move exactly one step from what is shown.
@MainActor
struct RepeatSyncTests {
    let rig = Rig()
    var coordinator: PlaybackCoordinator { rig.coordinator }

    private func begin() async {
        coordinator.start()
        await coordinator.refresh()
        #expect(coordinator.authority == .local)
        #expect(coordinator.snapshot.repeatMode == .off)
    }

    // Lets every overlay grace period and scheduled sync run out, in steps the scheduled work can follow.
    private func pass(_ seconds: TimeInterval) async {
        for _ in 0..<Int(seconds * 4) {
            rig.clock.advance(by: 0.25)
            await settle()
        }
    }

    private func click() async {
        await coordinator.cycleRepeat()
        await pass(4)
    }

    // The owner's report: within one track, repeat-one, then off, then on again showed repeat-one.
    @Test func repeatComingBackOnAfterRepeatOneIsRepeatContext() async {
        await begin()
        await click()
        #expect(coordinator.snapshot.repeatMode == .context)
        await click()
        #expect(coordinator.snapshot.repeatMode == .track)
        await click()
        #expect(coordinator.snapshot.repeatMode == .off)
        await click()
        #expect(await rig.spotify.repeatState == .context)
        #expect(coordinator.snapshot.repeatMode == .context)
    }

    @Test func eachClickAdvancesOneStepAndMatchesSpotify() async {
        await begin()
        let expected: [RepeatMode] = [.context, .track, .off, .context, .track, .off]
        for mode in expected {
            await click()
            #expect(coordinator.snapshot.repeatMode == mode)
            #expect(await rig.spotify.repeatState == mode)
        }
        #expect(coordinator.lastError == nil)
    }

    @Test func signedInRepeatGoesThroughTheWebAPI() async {
        await begin()
        for _ in 0..<3 { await click() }
        #expect(await rig.webRequests("setRepeat") == 3)
        #expect(await rig.localCommands("set repeating") == 0)
    }

    // A local read arriving while repeat-one is in flight says only "on"; if the command fails, what Spotify was
    // doing before (repeat-context) must show, not the optimistic repeat-one.
    @Test func aFailedRepeatOneLeavesTheModeSpotifyWasIn() async throws {
        await rig.spotify.failWebRequest("playbackState", with: .network(detail: "offline"))
        await begin()
        await coordinator.setRepeat(.context)
        await pass(4)
        #expect(coordinator.snapshot.repeatMode == .context)

        await rig.spotify.failWebRequest("setRepeat", with: .deviceRestricted)
        await rig.spotify.holdCommands()
        let coordinator = coordinator
        let cycling = Task { await coordinator.cycleRepeat() }
        #expect(await eventually { await rig.spotify.heldRequestCount == 1 })
        #expect(coordinator.snapshot.repeatMode == .track)
        let state = try #require(await rig.spotify.currentLocalState())
        await rig.spotify.emitLocalState(state)
        await settle()
        await rig.spotify.releaseHeld()
        await cycling.value
        await pass(4)
        #expect(coordinator.lastError == .deviceRestricted)
        #expect(await rig.spotify.repeatState == .context)
        #expect(coordinator.snapshot.repeatMode == .context)
    }

    @Test func aLocalReadNeverDowngradesAKnownRepeatOne() async throws {
        await begin()
        await coordinator.setRepeat(.track)
        await pass(4)
        #expect(coordinator.snapshot.repeatMode == .track)
        await coordinator.refresh()
        #expect(coordinator.snapshot.repeatMode == .track)
        // A notification without Automation details carries no repeat value at all.
        var bare = try #require(await rig.spotify.currentLocalState())
        bare.isRepeating = nil
        bare.isShuffling = nil
        bare.volume = nil
        await rig.spotify.emitLocalState(bare)
        await settle()
        #expect(coordinator.snapshot.repeatMode == .track)
    }

    // Repeat-one turned on in Spotify itself reads locally as plain "on"; the Web API is asked which one it is.
    @Test func repeatOneSetInSpotifyIsLearnedFromTheWebAPI() async {
        await begin()
        await rig.spotify.simulateRepeatChangedInApp(.track)
        await pass(2)
        #expect(coordinator.snapshot.repeatMode == .track)
        await click()
        #expect(coordinator.snapshot.repeatMode == .off)
        #expect(await rig.spotify.repeatState == .off)
    }

    // The Web API can describe the state from before a command for a moment; that must not undo repeat-one.
    @Test func aLaggingWebReadDoesNotUndoRepeatOne() async {
        await begin()
        await click()
        await rig.spotify.lagPlaybackState(reads: 1)
        await click()
        #expect(await rig.spotify.repeatState == .track)
        #expect(coordinator.snapshot.repeatMode == .track)
    }

    // Signed out, AppleScript can only turn repeat on or off, so the cycle skips repeat-one.
    @Test func signedOutRepeatCyclesOnAndOffLocally() async {
        coordinator.setWebAPIAvailable(false)
        await begin()
        #expect(!coordinator.snapshot.allows(.toggleRepeatTrack))
        for mode: RepeatMode in [.context, .off, .context] {
            await click()
            #expect(coordinator.snapshot.repeatMode == mode)
            #expect(await rig.spotify.repeatState == mode)
        }
        #expect(await rig.localCommands("set repeating") == 3)
        #expect(await rig.spotify.webRequests.isEmpty)
    }
}
