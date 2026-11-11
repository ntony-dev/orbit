import Foundation
import OrbitCore
import OrbitEngine
import OrbitMocks
import SpotifyKit

struct Services {
    let localPlayer: any LocalPlayer
    let api: any SpotifyAPI
    let authorizer: any Authorizer
}

// The only place concrete services are constructed. Mocks are reachable solely through the explicit --demo flag.
@MainActor
enum CompositionRoot {
    static func services(usingMocks: Bool, preferences: Preferences) async -> Services {
        if usingMocks {
            let mocks = await MockServices.demo()
            return Services(localPlayer: mocks.localPlayer, api: mocks.api, authorizer: mocks.authorizer)
        }
        let authorizer = SpotifyAuthorizer { @MainActor in
            resolveClientID(override: preferences.clientIDOverride, bundle: .main)
        }
        return Services(
            localPlayer: SpotifyAppleScriptPlayer(),
            api: SpotifyWebClient(authorizer: authorizer),
            authorizer: authorizer
        )
    }

    // The in-app override wins over the build-time Info.plist value fed by Config/Local.xcconfig.
    static func resolveClientID(override: String?, bundle: Bundle) -> String? {
        let candidates = [override, bundle.object(forInfoDictionaryKey: "SpotifyClientID") as? String]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("$(") }
    }
}
