import AppKit
import ImageIO
import OrbitCore
import OrbitEngine
import OrbitMocks
@testable import OrbitUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

// Renders panel states to PNG offscreen so layout and copy can be reviewed without a running app, including
// scenario states. Native glass is drawn by the window server, so these show Orbit's backing layer over a stand-in
// wallpaper instead of real glass, and symbol tints are unreliable in light mode; real window captures remain the
// reference for color. Runs only when ORBIT_SNAPSHOT_DIR is set.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] != nil))
struct SnapshotRenderingTests {
    // One appearance per run (ORBIT_SNAPSHOT_SCHEME=light, otherwise dark), since AppKit caches resolved symbol
    // images per process.
    static let schemes: [ColorScheme] = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_SCHEME"] == "light" ? [.light] : [.dark]

    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    @Test func renderStandardStates() async throws {
        let harness = try await SnapshotHarness.make(scenario: nil)
        for scheme in Self.schemes {
            let suffix = scheme == .dark ? "dark" : "light"
            try harness.renderPill(.regular, scheme: scheme, hovered: false, to: directory.appending(path: "pill-regular-\(suffix).png"))
            try harness.renderPill(.regular, scheme: scheme, hovered: true, to: directory.appending(path: "pill-regular-hover-\(suffix).png"))
            try harness.renderPill(.compact, scheme: scheme, hovered: false, to: directory.appending(path: "pill-compact-\(suffix).png"))
            try harness.renderPill(.compact, scheme: scheme, hovered: true, to: directory.appending(path: "pill-compact-hover-\(suffix).png"))
            try harness.render(scheme: scheme, to: directory.appending(path: "player-\(suffix).png")) { _ in }
            try harness.render(scheme: scheme, to: directory.appending(path: "library-\(suffix).png")) { $0.show(.library) }
            try harness.render(scheme: scheme, to: directory.appending(path: "search-\(suffix).png")) {
                $0.show(.library)
                $0.searchQuery = "night"
            }
            try harness.render(scheme: scheme, to: directory.appending(path: "devices-\(suffix).png")) { $0.drawer = .devices }
            try harness.render(scheme: scheme, to: directory.appending(path: "queue-\(suffix).png")) { $0.drawer = .queue }
            try harness.render(scheme: scheme, to: directory.appending(path: "playlist-\(suffix).png")) {
                $0.show(.library)
                $0.push(.playlist(MockFixtures.playlists[0]))
            }
            try harness.render(scheme: scheme, to: directory.appending(path: "playlist-restricted-\(suffix).png")) {
                $0.show(.library)
                $0.push(.playlist(MockFixtures.playlists.first { !$0.canReadItems }!))
            }
        }
        try harness.render(scheme: .dark, accent: .mint, to: directory.appending(path: "library-mint-dark.png")) { $0.show(.library) }
        try harness.render(scheme: .light, accent: .ice, to: directory.appending(path: "player-ice-light.png")) { _ in }
        try harness.render(scheme: .dark, contrast: .increased, to: directory.appending(path: "player-contrast-dark.png")) { _ in }
    }

    @Test(arguments: DemoScenario.allCases)
    func renderScenario(_ scenario: DemoScenario) async throws {
        let harness = try await SnapshotHarness.make(scenario: scenario)
        for scheme in Self.schemes {
            let suffix = scheme == .dark ? "dark" : "light"
            try harness.render(scheme: scheme, to: directory.appending(path: "\(scenario.rawValue)-player-\(suffix).png")) { _ in }
            try harness.render(scheme: scheme, to: directory.appending(path: "\(scenario.rawValue)-library-\(suffix).png")) { $0.show(.library) }
            try harness.renderPill(.regular, scheme: scheme, hovered: false, to: directory.appending(path: "\(scenario.rawValue)-pill-\(suffix).png"))
        }
    }
}

@MainActor
private final class NullHost: PanelHost {
    func setCanvasSize(_ size: CGSize) {}
    func beginDrag() {}
    func updateDrag() {}
    func endDrag() {}
    func setAcceptsKeyboardInput(_ accepts: Bool) {}
}

@MainActor
private struct SnapshotHarness {
    let stores: OrbitStores
    let panel = PanelState()
    let host = NullHost()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "orbit.ui.snapshots")!)
    let switcher = PlaylistSwitcher()

    static func make(scenario: DemoScenario?) async throws -> SnapshotHarness {
        let stores: OrbitStores
        if let scenario {
            let services = await scenario.services()
            stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        } else {
            let services = await MockServices.demo()
            stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        }
        stores.start()
        for _ in 0..<40 where stores.account.authState == .unknown || stores.playback.snapshot.sampledAt == .distantPast {
            try await Task.sleep(for: .milliseconds(100))
        }
        if stores.account.authState.isSignedIn {
            for _ in 0..<20 where stores.account.profile == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            await stores.library.loadPlaylists()
            await stores.library.loadSavedTracks()
            await stores.library.loadDevices()
            await stores.library.loadQueue()
            await stores.library.search("night")
            await stores.library.loadItems(for: MockFixtures.playlists[0])
            await stores.library.loadItems(for: MockFixtures.playlists.first { !$0.canReadItems }!)
            stores.library.pin(MockFixtures.playlists[2])
            stores.library.pin(MockFixtures.playlists[5])
            stores.library.recordRecent(MockFixtures.playlists[8])
            stores.library.recordRecent(MockFixtures.playlists[1])
        }
        await stores.playback.refresh()
        await prewarmArtwork()
        return SnapshotHarness(stores: stores)
    }

    // The render happens right after layout, before `.task` loads finish, so artwork must already be in the memory
    // cache that ArtworkView reads synchronously.
    private static func prewarmArtwork() async {
        let urls = MockFixtures.albums.compactMap(\.artworkURL) + MockFixtures.playlists.compactMap(\.artworkURL)
        let sizes: [CGFloat] = [26, 30, 34, 64, 76]
        for url in urls {
            for size in sizes {
                _ = await ArtworkPipeline.shared.artwork(for: ArtworkKey(url: url, pixelSize: ArtworkView.pixels(size, scale: 2)))
            }
        }
    }

    func theme(accent: AccentChoice = .neutral, contrast: ColorSchemeContrast = .standard) -> OrbitTheme {
        var theme = OrbitTheme.standard
        theme.accent = OrbitPalette.accent(accent)
        theme.contrast = contrast
        // Stand-in for the glass, which only the window server draws: a denser backing keeps text legible here.
        theme.backgroundOpacity = 1
        return theme
    }

    func render(
        scheme: ColorScheme,
        accent: AccentChoice = .neutral,
        contrast: ColorSchemeContrast = .standard,
        to url: URL,
        configure: (PanelNavigator) -> Void
    ) throws {
        let navigator = PanelNavigator()
        configure(navigator)
        var size = navigator.screenSize
        if navigator.section == .player, navigator.detail == nil,
           PlayerNoticeKind.current(account: stores.account, playback: stores.playback) != nil {
            size.height += PlayerNoticeKind.height
        }
        try write(GlassSurface(size: size) { ExpandedView().frame(width: size.width, height: size.height) },
                  size: size, scheme: scheme, navigator: navigator, theme: theme(accent: accent, contrast: contrast), to: url)
    }

    func renderPill(_ pillSize: PillSize, scheme: ColorScheme, hovered: Bool, to url: URL) throws {
        let size = OrbitTokens.Size.pill(pillSize)
        try write(GlassSurface(size: size, interactive: true) { PillView(size: size, forcesHover: hovered, onExpand: {}) },
                  size: size, scheme: scheme, navigator: PanelNavigator(), theme: theme(), to: url)
    }

    private func write(_ surface: some View, size: CGSize, scheme: ColorScheme, navigator: PanelNavigator, theme: OrbitTheme, to url: URL) throws {
        let margin: CGFloat = 28
        let view = surface
            .padding(margin)
            .background(Wallpaper(scheme: scheme))
            .modifier(PanelEnvironment(
                stores: stores, panel: panel, host: host, preferences: preferences,
                navigator: navigator, switcher: switcher, theme: theme
            ))
            .environment(\.colorScheme, scheme)
            .frame(width: size.width + margin * 2, height: size.height + margin * 2)
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        let frame = NSRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2)
        NSApplication.shared.appearance = appearance
        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame
        hosting.appearance = appearance
        // Never ordered on screen: the window only gives AppKit-backed pieces (scroll views, text fields) a
        // backing store to draw into.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(frame.width * 2), pixelsHigh: Int(frame.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = frame.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let cgImage = try #require(rep.cgImage)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

private struct Wallpaper: View {
    let scheme: ColorScheme

    var body: some View {
        if scheme == .dark {
            LinearGradient(colors: [Color(red: 0.14, green: 0.22, blue: 0.29), Color(red: 0.35, green: 0.38, blue: 0.47), Color(red: 0.55, green: 0.45, blue: 0.52)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            LinearGradient(colors: [Color(red: 0.78, green: 0.85, blue: 0.93), Color(red: 0.93, green: 0.88, blue: 0.86), Color(red: 0.86, green: 0.9, blue: 0.84)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
