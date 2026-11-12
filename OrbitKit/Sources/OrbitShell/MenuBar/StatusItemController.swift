import AppKit
import KeyboardShortcuts
import OrbitCore
import OrbitEngine
import OrbitUI

// The way back into Orbit when the pill is hidden, and the same essentials as the pill without opening it.
// The menu is rebuilt each time it opens, so it never needs to observe the stores while closed.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private unowned let shell: Shell
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var artwork: (url: URL, image: NSImage)?
    private var artworkLoad: Task<Void, Never>?

    init(shell: Shell) {
        self.shell = shell
        super.init()
        statusItem.button?.image = OrbitGlyph.menuBarImage()
        statusItem.button?.setAccessibilityLabel("Orbit")
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    // While a menu tracks, Carbon hot keys are queued and fire when it closes. The items show the same key
    // equivalents, so a shortcut pressed with the menu open would run twice: once from the item, once afterwards.
    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.disable(ShortcutAction.allCases.map(shell.shortcuts.name(for:)))
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(ShortcutAction.allCases.map(shell.shortcuts.name(for:)))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Each shortcut binding holds a NotificationCenter observer that outlives its item unless it is unbound.
        for item in menu.items { item.setShortcut(for: nil) }
        menu.removeAllItems()
        let playback = shell.stores.playback
        let snapshot = playback.snapshot

        menu.addItem(nowPlayingItem(snapshot))
        menu.addItem(.separator())
        let isPlaying = snapshot.isPlaying
        menu.addItem(item(isPlaying ? "Pause" : "Play", symbol: isPlaying ? "pause.fill" : "play.fill",
                          shortcut: .togglePlayback, enabled: snapshot.track != nil) { $0.perform(.togglePlayback) })
        menu.addItem(item("Next Track", symbol: "forward.fill", shortcut: .nextTrack,
                          enabled: snapshot.allows(.skipNext)) { $0.perform(.nextTrack) })
        menu.addItem(item("Previous Track", symbol: "backward.fill", shortcut: .previousTrack,
                          enabled: snapshot.allows(.skipPrevious)) { $0.perform(.previousTrack) })
        menu.addItem(.separator())
        menu.addItem(item("Open Player", symbol: "rectangle.portrait", shortcut: .toggleOrbit) { $0.panel.present(.player) })
        menu.addItem(item("Library…", symbol: "square.stack", shortcut: .openLibrary) { $0.panel.present(.playlistPicker) })
        menu.addItem(item("Search…", symbol: "magnifyingglass", shortcut: .focusSearch) { $0.panel.present(.search) })
        menu.addItem(.separator())
        let showsPill = shell.preferences.isPillVisible
        menu.addItem(item(showsPill ? "Hide Pill" : "Show Pill", symbol: showsPill ? "eye.slash" : "eye") {
            $0.preferences.isPillVisible.toggle()
        })
        menu.addItem(item("Reset Position", symbol: "arrow.down.right.and.arrow.up.left") { $0.panel.resetPosition() })
        menu.addItem(.separator())
        menu.addItem(item("About Orbit", symbol: "info.circle") { $0.showAbout() })
        let settings = item("Settings…", symbol: "gearshape") { $0.showSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = item("Quit Orbit", symbol: nil) { _ in NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func nowPlayingItem(_ snapshot: PlaybackSnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        if let track = snapshot.track {
            item.title = track.name
            item.subtitle = [track.artistLine, snapshot.device.map { "on \($0.name)" }].compactMap(\.self).joined(separator: " — ")
            item.image = artworkImage(for: track.artworkURL)
        } else {
            let account = shell.stores.account
            item.title = !account.isSpotifyInstalled ? "Spotify isn't installed"
                : !account.isSpotifyRunning ? "Spotify isn't running"
                : "Nothing playing"
            item.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        }
        return item
    }

    private func item(
        _ title: String,
        symbol: String?,
        shortcut: ShortcutAction? = nil,
        enabled: Bool = true,
        action: @escaping @MainActor (Shell) -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title) { [unowned shell] in action(shell) }
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        item.isEnabled = enabled
        // Shows the user's global shortcut beside the item; KeyboardShortcuts keeps it current.
        if let shortcut { item.setShortcut(for: shell.shortcuts.name(for: shortcut)) }
        return item
    }

    // Through the artwork pipeline, so the cover the pill already shows is usually decoded or on disk, and a
    // download is decoded off the main actor at the item's size rather than in full.
    private func artworkImage(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let artwork, artwork.url == url { return artwork.image }
        artworkLoad?.cancel()
        let side: CGFloat = 32
        let scale = statusItem.button?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if let cached = ArtworkImages.cached(url, points: side, scale: scale) {
            let image = NSImage(cgImage: cached, size: NSSize(width: side, height: side))
            artwork = (url, image)
            return image
        }
        artworkLoad = Task { [weak self] in
            guard let decoded = await ArtworkImages.load(url, points: side, scale: scale), !Task.isCancelled else { return }
            let image = NSImage(cgImage: decoded, size: NSSize(width: side, height: side))
            self?.artwork = (url, image)
            // The menu may still be open; the item picks the image up in place.
            self?.menu.items.first?.image = image
        }
        return NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
    }
}

@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
