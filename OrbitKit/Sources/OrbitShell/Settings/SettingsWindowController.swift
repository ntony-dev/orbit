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
    private var previousApp: NSRunningApplication?
    // Top-right corner the window keeps while it was placed for --settings; the tab controller resizes the window
    // to each pane after it is on screen.
    private var pinnedTopRight: CGPoint?

    init(shell: Shell) {
        self.shell = shell
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // The frame is saved in the standard defaults, which a throwaway demo run must not write to.
        if !shell.isDemo { window.setFrameAutosaveName("OrbitSettings") }
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

    // For the --settings launch argument: behind every other window, against the trailing edge of the display
    // holding `point` (the --panel-anchor, else the main display), so a capture run never lands on the side of
    // the screen the user is working in.
    func orderBackAtTrailingEdge(near point: CGPoint?) {
        guard let window else { return }
        let screen = point.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            pinnedTopRight = CGPoint(x: visible.maxX, y: visible.maxY)
            keepPinnedCorner()
        }
        window.orderBack(nil)
    }

    // Settings is the only reason Orbit is ever the active app. Once it closes, Orbit has no window to type into,
    // so activation goes back to the app the user came from instead of leaving keystrokes with nowhere to go.
    func returnsActivation(to app: NSRunningApplication?) {
        guard let app, app != NSRunningApplication.current else { return }
        previousApp = app
    }

    func windowDidResize(_ notification: Notification) {
        keepPinnedCorner()
    }

    private func keepPinnedCorner() {
        guard let pinnedTopRight, let window else { return }
        window.setFrameTopLeftPoint(CGPoint(x: pinnedTopRight.x - window.frame.width, y: pinnedTopRight.y))
    }

    func windowWillClose(_ notification: Notification) {
        pinnedTopRight = nil
        guard let previousApp, NSApp.isActive else { return }
        NSApp.yieldActivation(to: previousApp)
        previousApp.activate()
        self.previousApp = nil
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
