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
    static let demoDefaultsSuite = "io.github.ntony46.orbit.demo"

    // Demo runs get a settings store that is wiped at every launch, so they never read or change the user's
    // real settings and always start from the documented defaults.
    static func preferences(usingMocks: Bool) -> Preferences {
        guard usingMocks, let defaults = UserDefaults(suiteName: demoDefaultsSuite) else { return Preferences() }
        defaults.removePersistentDomain(forName: demoDefaultsSuite)
        return Preferences(defaults: defaults)
    }

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

extension CompositionRoot {
    // Real sessions keep pins and recents on disk and honor the preferred device. Demo sessions get the throwaway
    // demo Preferences and no shelf file, so fixtures never land in the user's library file.
    static func stores(for services: Services, usingMocks: Bool, preferences: Preferences) -> OrbitStores {
        OrbitStores(
            localPlayer: services.localPlayer,
            api: services.api,
            authorizer: services.authorizer,
            preferences: preferences,
            shelfFile: usingMocks ? nil : LibraryShelfFile(url: LibraryShelfFile.defaultURL)
        )
    }

    // `--demo --ui-scenario NAME` in Debug builds: the whole app, not only the panel, runs against that scenario,
    // so the menu bar, Settings and visibility rules see the same state the UI shows.
    static func scenarioServices(named name: String?) async -> Services? {
        #if DEBUG
        guard let scenario = name.flatMap(DemoScenario.init(rawValue:)) else { return nil }
        let services = await scenario.services()
        return Services(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        #else
        return nil
        #endif
    }
}
