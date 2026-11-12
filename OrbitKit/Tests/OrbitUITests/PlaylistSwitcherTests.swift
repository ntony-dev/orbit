import OrbitCore
import OrbitEngine
import OrbitMocks
@testable import OrbitUI
import Testing

@MainActor
struct PlaylistSwitcherTests {
    private let uri = MockFixtures.playlists[1].uri

    @Test func outcomeComesFromTheReturnValueNotOnlyTheSharedError() {
        #expect(PlaylistSwitcher.Outcome(started: true, error: nil) == .started)
        #expect(PlaylistSwitcher.Outcome(started: false, error: .playbackNotConfirmed) == .failed(.playbackNotConfirmed))
        // A replaced switch ends with no error; it must not be mistaken for a success.
        #expect(PlaylistSwitcher.Outcome(started: false, error: nil) == .superseded)
    }

    @Test func aSupersededSwitchNeitherConfirmsNorCollapses() async {
        let switcher = PlaylistSwitcher()
        var collapsed = false
        await switcher.settle(uri, .superseded, collapse: { collapsed = true })
        #expect(switcher.confirmed == nil)
        #expect(switcher.failure(for: uri) == nil)
        #expect(!collapsed)
    }

    @Test func aFailedSwitchIsRecordedAndNeverConfirmed() async {
        let switcher = PlaylistSwitcher()
        var collapsed = false
        await switcher.settle(uri, .failed(.playbackNotConfirmed), collapse: { collapsed = true })
        #expect(switcher.confirmed == nil)
        #expect(switcher.failure(for: uri) == .playbackNotConfirmed)
        #expect(!collapsed)
    }

    // The demo scenario used to fail only the Web API route, while the demo's active device is this Mac, so the
    // switch went over AppleScript and succeeded.
    @Test(.timeLimit(.minutes(1)))
    func switchFailsScenarioReallyFailsASwitch() async throws {
        let services = await DemoScenario.switchFails.services()
        let stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        stores.start()
        for _ in 0..<40 where stores.playback.snapshot.track == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        // The simulated Spotify starts in the first fixture playlist.
        let target = try #require(MockFixtures.playlists.dropFirst().first { MockFixtures.playlistTracks[$0.id]?.isEmpty == false })
        let switcher = PlaylistSwitcher()
        await switcher.play(target, with: stores.playback, thenCollapse: nil)
        #expect(switcher.failure(for: target.uri) != nil)
        #expect(switcher.confirmed == nil)
        #expect(stores.playback.snapshot.context?.uri != target.uri)
        stores.playback.stop()
    }
}
