import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Sendable {
    case appearance, behavior, spotify, shortcuts

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .behavior: "Behavior"
        case .spotify: "Spotify"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .behavior: "macwindow.on.rectangle"
        case .spotify: "music.note"
        case .shortcuts: "keyboard"
        }
    }
}

// A classic preferences window: toolbar tabs, one pane at a time, the window resizing to fit each pane.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let tabs = NSTabViewController()
    private unowned let shell: Shell

    init(shell: Shell) {
        self.shell = shell
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OrbitSettings")
        super.init(window: window)
        window.delegate = self
        for pane in SettingsPane.allCases {
            let controller = NSHostingController(rootView: content(for: pane))
            controller.sizingOptions = .preferredContentSize
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            item.identifier = pane.rawValue
            tabs.addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func select(_ pane: SettingsPane) {
        tabs.selectedTabViewItemIndex = SettingsPane.allCases.firstIndex(of: pane) ?? 0
    }

    // Login item approval and Automation consent change in System Settings, so re-read them on every return.
    func windowDidBecomeKey(_ notification: Notification) {
        shell.loginItem.refresh()
        Task { await shell.stores.account.refreshLocalStatus() }
    }

    private func content(for pane: SettingsPane) -> AnyView {
        switch pane {
        case .appearance: AnyView(AppearancePane(preferences: shell.preferences))
        case .behavior: AnyView(BehaviorPane(preferences: shell.preferences, loginItem: shell.loginItem, panel: shell.panel))
        case .spotify: AnyView(SpotifyPane(stores: shell.stores, preferences: shell.preferences))
        case .shortcuts: AnyView(ShortcutsPane(shortcuts: shell.shortcuts))
        }
    }
}
