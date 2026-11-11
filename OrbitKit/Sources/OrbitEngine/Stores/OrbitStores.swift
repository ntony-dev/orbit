import Observation
import OrbitCore

// Owns the three stores and the links between them, so views receive one object per concern.
@MainActor
public final class OrbitStores {
    public let playback: PlaybackCoordinator
    public let library: LibraryStore
    public let account: AccountStore

    private var authObservation: Task<Void, Never>?

    public init(localPlayer: any LocalPlayer, api: any SpotifyAPI, authorizer: any Authorizer) {
        playback = PlaybackCoordinator(localPlayer: localPlayer, api: api)
        library = LibraryStore(api: api)
        account = AccountStore(authorizer: authorizer, api: api, localPlayer: localPlayer)
        playback.contextStarted = { [library] playlist in library.recordRecent(playlist) }
    }

    public func start() {
        account.start()
        playback.start()
        guard authObservation == nil else { return }
        let account = account
        let library = library
        authObservation = Task {
            for await state in Observations({ account.authState }) where state == .signedIn {
                await library.loadPlaylists()
                await library.loadDevices()
            }
        }
    }
}
