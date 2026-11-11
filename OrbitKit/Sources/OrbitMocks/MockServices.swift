import Foundation
import OrbitCore

public struct MockServices: Sendable {
    public let spotify: MockSpotify
    public let localPlayer: MockLocalPlayer
    public let api: MockSpotifyAPI
    public let authorizer: MockAuthorizer

    public init(spotify: MockSpotify = MockSpotify(), authorizer: MockAuthorizer = MockAuthorizer()) {
        self.spotify = spotify
        localPlayer = MockLocalPlayer(spotify: spotify)
        api = MockSpotifyAPI(spotify: spotify)
        self.authorizer = authorizer
    }

    // Renders fixture artwork off the main thread and starts the playback clock, for `--demo` and previews.
    public static func demo() async -> MockServices {
        await Task.detached(priority: .userInitiated) { MockArtwork.render(MockFixtures.artwork) }.value
        let services = MockServices()
        await services.spotify.startClock()
        return services
    }
}
