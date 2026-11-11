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

    init(isDemo: Bool, preferences: Preferences, services: Services) {
        self.isDemo = isDemo
        self.preferences = preferences
        stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        panel = PanelController(stores: stores, preferences: preferences)
        shortcuts = GlobalShortcuts(isDemo: isDemo)
        loginItem = LoginItem(isAvailable: !isDemo)
    }

    func start(options: LaunchOptions) {
        stores.start()
        panel.start(pinnedAt: options.anchorPoint, expanded: options.startsExpanded)
        statusItem = StatusItemController(shell: self)
        shortcuts.start { [unowned self] in perform($0) }
        if let pane = options.settingsPane { showSettings(pane, inBackground: true) }
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

    // `inBackground` is for the --settings launch argument: the window is put behind every other window and Orbit
    // is not activated, so it can be captured by window ID without disturbing whoever is using the Mac.
    func showSettings(_ pane: SettingsPane? = nil, inBackground: Bool = false) {
        let controller = settingsWindow ?? SettingsWindowController(shell: self)
        settingsWindow = controller
        if let pane { controller.select(pane) }
        if inBackground {
            controller.window?.orderBack(nil)
        } else {
            NSApp.activate()
            controller.showWindow(nil)
        }
    }
}
