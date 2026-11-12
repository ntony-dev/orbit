import AppKit
import OrbitCore
import OrbitEngine

// Everything the running app is made of, wired once in AppDelegate and shared by the menu bar item, global
// shortcuts and the Settings window.
@MainActor
final class Shell {
    let isDemo: Bool
    let preferences: Preferences
    let stores: OrbitStores
    let panel: PanelController
    let shortcuts: GlobalShortcuts
    let loginItem: LoginItem
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var syncFrequencyObservation: Task<Void, Never>?

    init(isDemo: Bool, preferences: Preferences, services: Services) {
        self.isDemo = isDemo
        self.preferences = preferences
        stores = CompositionRoot.stores(for: services, usingMocks: isDemo, preferences: preferences)
        panel = PanelController(stores: stores, preferences: preferences)
        shortcuts = GlobalShortcuts(isDemo: isDemo)
        loginItem = LoginItem(isAvailable: !isDemo)
    }

    func start(options: LaunchOptions) {
        // Both flags exist only with --demo, whose Preferences and Spotify are throwaway.
        if options.startsWithPillHidden { preferences.isPillVisible = false }
        observeSyncFrequency()
        stores.start()
        if options.startsPaused {
            let playback = stores.playback
            Task {
                await playback.refresh()
                if playback.snapshot.isPlaying { await playback.togglePlayPause() }
            }
        }
        panel.start(pinnedAt: options.anchorPoint, expanded: options.startsExpanded)
        statusItem = StatusItemController(shell: self)
        shortcuts.start { [unowned self] in perform($0) }
        if let pane = options.settingsPane { showSettingsInBackground(pane, near: options.anchorPoint) }
    }

    // Set before the stores start, so the first sync already follows the user's setting.
    private func observeSyncFrequency() {
        let playback = stores.playback
        let preferences = preferences
        playback.syncFrequency = preferences.syncFrequency
        syncFrequencyObservation = Task {
            for await frequency in Observations({ preferences.syncFrequency }) {
                playback.syncFrequency = frequency
            }
        }
    }

    func perform(_ action: ShortcutAction) {
        let playback = stores.playback
        switch action {
        case .toggleOrbit: panel.toggle()
        case .focusSearch: panel.present(.search)
        case .openPlaylistPicker: panel.present(.playlistPicker)
        case .togglePlayback: Task { await playback.togglePlayPause() }
        case .nextTrack: Task { await playback.next() }
        case .previousTrack: Task { await playback.previous() }
        }
    }

    func showSettings(_ pane: SettingsPane? = nil) {
        let controller = settingsController(selecting: pane)
        controller.returnsActivation(to: NSWorkspace.shared.frontmostApplication)
        NSApp.activate()
        controller.showWindow(nil)
    }

    // The standard About panel, with the third-party notices bundled as Acknowledgements.txt as its credits.
    func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            options[.credits] = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    // For the --settings launch argument: the window is put behind every other window and Orbit is not activated,
    // so it can be captured by window ID without disturbing whoever is using the Mac.
    private func showSettingsInBackground(_ pane: SettingsPane, near point: CGPoint?) {
        settingsController(selecting: pane).orderBackAtTrailingEdge(near: point)
    }

    private func settingsController(selecting pane: SettingsPane?) -> SettingsWindowController {
        let controller = settingsWindow ?? SettingsWindowController(shell: self)
        settingsWindow = controller
        if let pane { controller.select(pane) }
        return controller
    }
}
