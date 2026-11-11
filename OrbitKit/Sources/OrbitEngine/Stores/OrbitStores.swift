import Foundation
import Observation
import OrbitCore

// Owns the three stores and the links between them, so views receive one object per concern.
@MainActor
public final class OrbitStores {
    public let playback: PlaybackCoordinator
    public let library: LibraryStore
    public let account: AccountStore

    private var observations: [Task<Void, Never>] = []

    // `shelfFile` persists pins and recents; pass `LibraryShelfFile(url: LibraryShelfFile.defaultURL)` for a real
    // session and nil for demo or previews so fixtures never land in the user's file.
    public init(
        localPlayer: any LocalPlayer,
        api: any SpotifyAPI,
        authorizer: any Authorizer,
        preferences: Preferences? = nil,
        shelfFile: LibraryShelfFile? = nil,
        clock: EngineClock = .system
    ) {
        playback = PlaybackCoordinator(localPlayer: localPlayer, api: api, clock: clock)
        library = LibraryStore(api: api, shelfFile: shelfFile, clock: clock)
        account = AccountStore(authorizer: authorizer, api: api, localPlayer: localPlayer)
        playback.setWebAPIAvailable(false)

        let library = library
        let account = account
        library.preferredDevice = { preferences?.preferredDevice }
        playback.contextStarted = { library.recordRecent($0) }
        playback.contextName = { library.playlist(for: $0)?.name }
        playback.contextTracks = { library.knownTrackURIs(for: $0) }
        playback.preferredDeviceID = {
            switch library.preferredDeviceStatus {
            case .available(let device): device.id
            case .unverified(let reference): reference.id
            case .notSet, .missing: nil
            }
        }
        playback.automationDenied = { Task { await account.refreshLocalStatus() } }
    }

    public func start() {
        account.start()
        playback.start()
        guard observations.isEmpty else { return }
        let account = account
        let library = library
        let playback = playback
        observations.append(Task { await library.restoreShelf() })
        observations.append(Task {
            for await state in Observations({ account.authState }) {
                switch state {
                case .signedIn:
                    playback.setWebAPIAvailable(true)
                    async let playlists: Void = library.loadPlaylists()
                    async let devices: Void = library.loadDevices()
                    _ = await (playlists, devices)
                case .signedOut:
                    playback.setWebAPIAvailable(false)
                    library.reset()
                case .unknown, .authorizing:
                    break
                }
            }
        })
        observations.append(Task {
            for await profile in Observations({ account.profile }) {
                library.setUser(profile)
            }
        })
        observations.append(Task {
            var previous: AutomationPermission?
            for await permission in Observations({ account.automationPermission }) {
                defer { previous = permission }
                guard previous != nil, permission != previous else { continue }
                await playback.refresh()
            }
        })
    }

    // The shell calls this whenever the panel expands, collapses to the pill, or hides entirely; it decides how
    // often playback is synced from the Web API and refreshes what an expanded panel shows.
    public func setInterfaceVisibility(_ visibility: InterfaceVisibility) {
        playback.setInterfaceVisibility(visibility)
        guard visibility == .expanded else { return }
        let account = account
        let library = library
        Task {
            await account.refreshLocalStatus()
            guard account.authState.isSignedIn else { return }
            async let playlists: Void = library.loadPlaylists()
            async let devices: Void = library.loadDevices()
            _ = await (playlists, devices)
        }
    }
}
