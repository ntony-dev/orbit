import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks

// One simulated Spotify behind a coordinator, with a manual clock so nothing in a test depends on wall time.
@MainActor
struct Rig {
    let clock = MockClock()
    let spotify: MockSpotify
    let services: MockServices
    let coordinator: PlaybackCoordinator

    var engineClock: EngineClock { EngineClock(now: clock.now, sleep: clock.sleep) }

    // `restoredState` is what the stored session restores to once `stores()` start.
    init(restoredState: AuthState = .signedIn) {
        spotify = MockSpotify(latency: .zero, now: clock.now)
        services = MockServices(spotify: spotify, authorizer: MockAuthorizer(restoredState: restoredState, latency: .zero))
        coordinator = PlaybackCoordinator(
            localPlayer: services.localPlayer,
            api: services.api,
            clock: EngineClock(now: clock.now, sleep: clock.sleep)
        )
    }

    func stores(shelfFile: LibraryShelfFile? = nil) -> OrbitStores {
        OrbitStores(
            localPlayer: services.localPlayer,
            api: services.api,
            authorizer: services.authorizer,
            shelfFile: shelfFile,
            clock: engineClock
        )
    }

    func webRequests(_ name: String) async -> Int {
        await spotify.webRequests.filter { $0 == name }.count
    }

    func localCommands(_ name: String) async -> Int {
        await spotify.localCommands.filter { $0 == name }.count
    }
}

// Lets queued main-actor work and mock actor hops run; the manual clock keeps this deterministic.
@MainActor
func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}

// For asserting that something does not happen: gives queued work a fixed number of turns to run first.
@MainActor
func settle() async {
    for _ in 0..<20 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

extension MockFixtures {
    static func playlist(_ id: String) -> Playlist {
        playlists.first { $0.id == id }!
    }

    static var startingPlaylist: Playlist { playlists[0] }
}
