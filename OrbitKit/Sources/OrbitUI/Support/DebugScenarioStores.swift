#if DEBUG
import OrbitEngine
import OrbitMocks

// Swaps in stores backed by a named DemoScenario. Reachable only in Debug builds and only alongside --demo (see
// UIDebugOptions), so mocks still never reach a release build or a real session.
@MainActor
enum DebugScenarioStores {
    static func make(named name: String) async -> OrbitStores? {
        guard let scenario = DemoScenario(rawValue: name) else { return nil }
        let services = await scenario.services()
        let stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        stores.start()
        return stores
    }
}
#endif
