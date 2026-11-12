import AppKit
import ImageIO
import OrbitCore
import OrbitEngine
import OrbitMocks
@testable import OrbitUI
import SwiftUI
import Testing
import UniformTypeIdentifiers

// Offscreen renders of pill and player states the demo app cannot be launched into: Automation permission not yet
// asked for, paused playback and a title too long for the pill. Layout and copy only; native glass and light-mode
// symbol tints need real window captures. Runs only when ORBIT_SNAPSHOT_DIR is set.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] != nil))
struct PillPlayerSnapshotTests {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())
    let scheme: ColorScheme = ProcessInfo.processInfo.environment["ORBIT_SNAPSHOT_SCHEME"] == "light" ? .light : .dark
    var suffix: String { scheme == .dark ? "dark" : "light" }

    @Test(arguments: [AuthState.signedOut, .signedIn])
    func automationNotYetAllowed(_ auth: AuthState) async throws {
        let spotify = MockSpotify()
        await spotify.setAutomationPermission(.notDetermined)
        let services = MockServices(spotify: spotify, authorizer: MockAuthorizer(restoredState: auth))
        let stores = try await Self.started(services)
        let name = auth == .signedIn ? "automation-needed-signed-in" : "automation-needed"
        for pill in PillSize.allCases {
            try render(pill: pill, stores: stores, hovered: false, to: "\(name)-pill-\(pill.rawValue)")
        }
        try renderPlayer(stores: stores, to: "\(name)-player")
    }

    @Test func pausedAndHovered() async throws {
        let services = MockServices()
        let stores = try await Self.started(services)
        await stores.playback.togglePlayPause()
        for pill in PillSize.allCases {
            try render(pill: pill, stores: stores, hovered: false, to: "paused-pill-\(pill.rawValue)")
            try render(pill: pill, stores: stores, hovered: true, to: "paused-pill-hover-\(pill.rawValue)")
        }
        try renderPlayer(stores: stores, to: "paused-player")
    }

    @Test func longTitlesFadeInsteadOfEllipsis() throws {
        let view = VStack(alignment: .leading, spacing: 6) {
            Text("A Title Far Too Long For The Pill To Hold").font(OrbitTokens.Typography.pillTitleRegular).fadingTruncation()
            Text("Short Title").font(OrbitTokens.Typography.pillTitleRegular).fadingTruncation()
        }
        .frame(width: 160)
        .padding(12)
        try write(view, size: CGSize(width: 184, height: 62), to: "fading-truncation")
    }

    private static func started(_ services: MockServices) async throws -> OrbitStores {
        _ = await MockServices.demo()
        let stores = OrbitStores(localPlayer: services.localPlayer, api: services.api, authorizer: services.authorizer)
        stores.start()
        for _ in 0..<40 where stores.account.authState == .unknown || stores.playback.snapshot.sampledAt == .distantPast {
            try await Task.sleep(for: .milliseconds(100))
        }
        await stores.account.refreshLocalStatus()
        await stores.playback.refresh()
        for url in MockFixtures.albums.compactMap(\.artworkURL) {
            for size: CGFloat in [26, 34, 76] {
                _ = await ArtworkPipeline.shared.artwork(for: ArtworkKey(url: url, pixelSize: ArtworkView.pixels(size, scale: 2)))
            }
        }
        return stores
    }

    private func render(pill: PillSize, stores: OrbitStores, hovered: Bool, to name: String) throws {
        let size = OrbitTokens.Size.pill(pill)
        let view = GlassSurface(size: size, interactive: true) { PillView(size: size, forcesHover: hovered, onExpand: {}) }
        try write(environment(view, stores: stores, navigator: PanelNavigator()), size: size, to: name)
    }

    private func renderPlayer(stores: OrbitStores, to name: String) throws {
        let navigator = PanelNavigator()
        var size = navigator.screenSize
        if PlayerNoticeKind.current(account: stores.account, playback: stores.playback) != nil {
            size.height += PlayerNoticeKind.height
        }
        let view = GlassSurface(size: size) { ExpandedView().frame(width: size.width, height: size.height) }
        try write(environment(view, stores: stores, navigator: navigator), size: size, to: name)
    }

    private func environment(_ view: some View, stores: OrbitStores, navigator: PanelNavigator) -> some View {
        var theme = OrbitTheme.standard
        theme.backgroundOpacity = 1
        return view.modifier(PanelEnvironment(
            stores: stores, panel: PanelState(), host: SnapshotHost(),
            preferences: Preferences(defaults: UserDefaults(suiteName: "orbit.ui.pill-snapshots")!),
            navigator: navigator, switcher: PlaylistSwitcher(), theme: theme
        ))
    }

    private func write(_ content: some View, size: CGSize, to name: String) throws {
        let margin: CGFloat = 24
        let frame = NSRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2)
        let view = content
            .padding(margin)
            .background(scheme == .dark ? Color(white: 0.3) : Color(white: 0.85))
            .environment(\.colorScheme, scheme)
            .frame(width: frame.width, height: frame.height)
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        NSApplication.shared.appearance = appearance
        let hosting = NSHostingView(rootView: view)
        hosting.frame = frame
        hosting.appearance = appearance
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
        let url = directory.appending(path: "\(name)-\(suffix).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(rep.cgImage), nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@MainActor
private final class SnapshotHost: PanelHost {
    func setCanvasSize(_ size: CGSize) {}
    func beginDrag() {}
    func updateDrag() {}
    func endDrag() {}
    func setAcceptsKeyboardInput(_ accepts: Bool) {}
}
