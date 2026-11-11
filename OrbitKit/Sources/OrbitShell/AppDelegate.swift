import AppKit
import OrbitCore
import OrbitEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let preferences = Preferences()
    private var stores: OrbitStores?
    private var panelController: PanelController?
    private var appearanceObservation: Task<Void, Never>?

    init(options: LaunchOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearance()
        Task { await launch() }
    }

    private func launch() async {
        let services = await CompositionRoot.services(usingMocks: options.usesMocks, preferences: preferences)
        let stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        stores.start()
        let controller = PanelController(stores: stores, preferences: preferences)
        controller.show(anchoredAt: options.anchorPoint, expanded: options.startsExpanded)
        self.stores = stores
        panelController = controller
    }

    private func observeAppearance() {
        if let forced = options.appearance {
            NSApp.appearance = Self.appearance(for: forced)
            return
        }
        let preferences = preferences
        appearanceObservation = Task {
            for await mode in Observations({ preferences.appearance }) {
                NSApp.appearance = Self.appearance(for: mode)
            }
        }
    }

    private static func appearance(for mode: AppearanceMode) -> NSAppearance? {
        switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
