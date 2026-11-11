import AppKit
import OrbitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let preferences: Preferences
    private var shell: Shell?
    private var appearanceObservation: Task<Void, Never>?

    init(options: LaunchOptions) {
        self.options = options
        preferences = CompositionRoot.preferences(usingMocks: options.usesMocks)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeAppearance()
        Task { await launch() }
    }

    private func launch() async {
        let services: Services
        if let scenario = await CompositionRoot.scenarioServices(named: options.demoScenario) {
            services = scenario
        } else {
            services = await CompositionRoot.services(usingMocks: options.usesMocks, preferences: preferences)
        }
        let shell = Shell(isDemo: options.usesMocks, preferences: preferences, services: services)
        self.shell = shell
        shell.start(options: options)
    }

    // Opening Orbit again from Finder or Spotlight while it runs is a request to see it, even with the pill hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shell?.panel.present()
        return false
    }

    // Reachable from any Orbit view with NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil),
    // so OrbitUI can offer a Settings button without depending on the shell.
    @objc func showSettingsWindow(_ sender: Any?) {
        shell?.showSettings()
    }

    // Applies app-wide, so the panel, menus and Settings all follow the user's choice.
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
