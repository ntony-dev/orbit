import OrbitCore
import OrbitEngine
import SwiftUI

// Fills the shell's transparent canvas with one glass surface anchored to the pill's corner. Expanding, collapsing
// and moving between screens only change that surface's size while its content cross-fades, so the user always
// sees a single object reshaping itself rather than windows being swapped.
public struct PanelRootView: View {
    private let panel: PanelState
    private let host: any PanelHost
    private let preferences: Preferences
    private let debug = UIDebugOptions.current

    @State private var stores: OrbitStores
    @State private var navigator = PanelNavigator()
    @State private var switcher = PlaylistSwitcher()
    @State private var isShowingExpanded = false
    @State private var allocatedCanvas: CGSize = .zero
    @State private var resizeGeneration = 0
    @State private var artworkTint: Color?

    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReducesTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast

    public init(stores: OrbitStores, panel: PanelState, host: any PanelHost, preferences: Preferences) {
        _stores = State(initialValue: stores)
        self.panel = panel
        self.host = host
        self.preferences = preferences
    }

    public var body: some View {
        let theme = resolvedTheme
        let surfaceSize = currentSurfaceSize
        GlassSurface(size: surfaceSize, interactive: !isShowingExpanded) {
            ZStack(alignment: Alignment(panel.anchor)) {
                if isShowingExpanded {
                    ExpandedView()
                        .frame(width: expandedSize.width, height: expandedSize.height)
                        .transition(expandedTransition(theme))
                } else {
                    PillView(size: pillSize, forcesHover: debug.forcesPillHover, onExpand: expandFromPill)
                        .frame(width: pillSize.width, height: pillSize.height)
                        .transition(pillTransition(theme))
                }
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height, alignment: Alignment(panel.anchor))
        }
        // Size changes that come from state rather than navigation, such as a notice appearing, still morph.
        .animation(theme.animation(OrbitTokens.Motion.morph), value: expandedSize)
        .padding(OrbitTokens.Size.canvasMargin)
        // The canvas takes its new size at once, exactly when the window does. Were it to animate, the hosting view
        // would centre the growing canvas in the window and carry the surface off its anchor, so a pill would jump
        // toward the middle of the card and grow from there.
        .animation(nil) { content in
            content.frame(width: allocatedCanvas.width, height: allocatedCanvas.height, alignment: Alignment(panel.anchor))
        }
        .background {
            if let backdrop = debug.backdrop { DebugBackdrop(style: backdrop) }
        }
        .modifier(PanelEnvironment(
            stores: stores, panel: panel, host: host, preferences: preferences,
            navigator: navigator, switcher: switcher, theme: theme
        ))
        .onAppear(perform: appear)
        .onChange(of: panel.isExpanded) { _, expanded in
            expanded ? expand() : collapse()
        }
        .onChange(of: panel.requestedDestination) { _, destination in
            guard let destination, isShowingExpanded else { return }
            withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.reset(to: destination) }
            panel.clearRequestedDestination()
        }
        .onChange(of: navigator.depth, initial: true) { _, depth in
            panel.openLayerCount = depth
        }
        .onChange(of: panel.layerDismissals) {
            withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { _ = navigator.back() }
        }
        .onChange(of: currentSurfaceSize) { _, size in
            fitCanvas(to: size)
        }
        .task(id: stores.playback.snapshot.track?.artworkURL) {
            await loadArtworkTint()
        }
        .task {
            await seedDebugShelf()
            await openPendingDebugPlaylist()
            await runDebugTour()
            await runDebugSwitch()
        }
    }

    private var resolvedTheme: OrbitTheme {
        OrbitTheme(
            accent: OrbitPalette.accent(debug.accent ?? preferences.accent),
            glassPreset: debug.glassPreset ?? preferences.glassPreset,
            backgroundOpacity: debug.backgroundOpacity ?? preferences.backgroundOpacity,
            showsArtwork: preferences.showsArtwork && !debug.hidesArtwork,
            reducesMotion: preferences.reducesAnimation || systemReducesMotion || debug.reducesMotion,
            reducesTransparency: systemReducesTransparency || debug.reducesTransparency,
            contrast: debug.increasesContrast ? .increased : systemContrast,
            artworkTint: artworkTint,
            animationSpeed: debug.animationSpeed
        )
    }

    // Through PanelMetrics, as the shell does, so a debug pill size reaches both sides.
    private var pillSize: CGSize {
        PanelMetrics.pillSize(preferences.pillSize)
    }

    private var expandedSize: CGSize {
        var size = navigator.screenSize
        if navigator.section == .player, navigator.detail == nil,
           PlayerNoticeKind.current(account: stores.account, playback: stores.playback) != nil {
            size.height += PlayerNoticeKind.height
        }
        // The account gate replaces every screen but the player with one short message and an action.
        if navigator.section != .player || navigator.detail != nil {
            switch stores.account.authState {
            case .signedOut, .authorizing: size.height = OrbitTokens.Size.gatedHeight
            case .unknown, .signedIn: break
            }
        }
        return size
    }

    private var currentSurfaceSize: CGSize {
        isShowingExpanded ? expandedSize : pillSize
    }

    // The pill fades out quickly so it never floats inside a growing card; the expanded content scales up from
    // the anchored corner as the surface reveals it. Collapsing overlaps the two fades, so the closing surface is
    // never empty for a beat. Reduced motion keeps only the fades.
    private func expandedTransition(_ theme: OrbitTheme) -> AnyTransition {
        let fadeIn = AnyTransition.opacity.animation(theme.animation(OrbitTokens.Motion.surfaceFadeIn))
        let fadeOut = AnyTransition.opacity.animation(theme.animation(OrbitTokens.Motion.collapseContentFadeOut))
        guard !theme.reducesMotion else { return .asymmetric(insertion: fadeIn, removal: fadeOut) }
        return .asymmetric(
            insertion: fadeIn.combined(with: .scale(scale: 0.94, anchor: UnitPoint(panel.anchor))),
            removal: fadeOut.combined(with: .scale(scale: 0.97, anchor: UnitPoint(panel.anchor)))
        )
    }

    private func pillTransition(_ theme: OrbitTheme) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(theme.animation(OrbitTokens.Motion.collapsePillFadeIn)),
            removal: .opacity.animation(theme.animation(OrbitTokens.Motion.pillFadeOut))
        )
    }

    private func appear() {
        if panel.isExpanded {
            navigator.reset(to: panel.requestedDestination ?? .player)
            panel.clearRequestedDestination()
            applyDebugScreen()
            isShowingExpanded = true
        }
        allocateCanvas(CanvasPlan.canvas(for: currentSurfaceSize))
        panel.isCanvasFitted = true
    }

    private func expandFromPill() {
        panel.expand(to: PlaybackStatus(account: stores.account, snapshot: stores.playback.snapshot).pillDestination)
    }

    private func expand() {
        navigator.reset(to: panel.requestedDestination ?? .player)
        panel.clearRequestedDestination()
        withAnimation(resolvedTheme.animation(OrbitTokens.Motion.morph)) { isShowingExpanded = true }
    }

    private func collapse() {
        withAnimation(resolvedTheme.animation(OrbitTokens.Motion.collapse)) { isShowingExpanded = false }
    }

    // Grows the canvas before the surface starts moving and shrinks it once the motion has settled. A newer
    // resize cancels an older pending shrink, so interrupted animations never clip the surface.
    private func fitCanvas(to surface: CGSize) {
        resizeGeneration += 1
        let generation = resizeGeneration
        panel.isCanvasFitted = false
        // Grown on the next turn of the run loop rather than inside the update that changed the surface: a window
        // resized from within a SwiftUI update reaches the hosting view in a later, animated update, which moves
        // the whole canvas off its anchor while it settles. The surface has barely started moving by then, and the
        // canvas margin covers it. Recomputed when it runs, so it only ever grows.
        DispatchQueue.main.async {
            let during = CanvasPlan.during(current: allocatedCanvas, target: surface)
            if during != allocatedCanvas { allocateCanvas(during) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: OrbitTokens.Motion.settle / resolvedTheme.animationSpeed)
            guard generation == resizeGeneration else { return }
            // Fitted to the surface as it is now: a list that re-fits from inside a layout pass (a playlist whose
            // tracks turn out to be unavailable, replacing the taller loading rows) can change the surface without
            // this view seeing the change, which left the canvas at the skeleton's height.
            if let after = CanvasPlan.after(current: allocatedCanvas, target: currentSurfaceSize) { allocateCanvas(after) }
            panel.isCanvasFitted = true
        }
    }

    // Outside the morph's transaction, so the window, the hosting view and the canvas frame all change in one
    // unanimated step while the surface inside keeps animating.
    private func allocateCanvas(_ size: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            allocatedCanvas = size
            host.setCanvasSize(size)
        }
    }

    private func loadArtworkTint() async {
        guard let url = stores.playback.snapshot.track?.artworkURL else {
            artworkTint = nil
            return
        }
        let key = ArtworkKey(url: url, pixelSize: ArtworkView.pixels(OrbitTokens.Size.nowPlayingArtwork, scale: 2))
        guard let average = await ArtworkPipeline.shared.artwork(for: key)?.averageColor, !Task.isCancelled else { return }
        // Pulled toward mid-grey so the tint reads as a hint of the cover, never a saturated wash.
        let muted = average * 0.6 + SIMD3(repeating: 0.4) * 0.4
        withAnimation(resolvedTheme.animation(OrbitTokens.Motion.content)) {
            artworkTint = Color(.sRGB, red: muted.x, green: muted.y, blue: muted.z)
        }
    }

    private func applyDebugScreen() {
        if let query = debug.searchQuery { navigator.searchQuery = query }
        guard let screen = debug.screen else { return }
        switch screen {
        // Search is the library with a query; focusing its field would ask for key status, which a capture must
        // never take.
        case "library", "picker", "search": navigator.show(.library)
        case "devices": navigator.drawer = .devices
        case "queue": navigator.drawer = .queue
        case "liked": openDebugPlaylist(LikedSongs.id)
        default:
            if screen.hasPrefix("playlist:") { openDebugPlaylist(String(screen.dropFirst("playlist:".count))) }
        }
    }

    @State private var pendingDebugPlaylistID: String?

    private func openDebugPlaylist(_ id: String) {
        navigator.show(.library)
        if let playlist = debugPlaylist(id) {
            navigator.push(.playlist(playlist))
        } else {
            pendingDebugPlaylistID = id
        }
    }

    private func debugPlaylist(_ id: String) -> Playlist? {
        if id == LikedSongs.id { return LikedSongs.playlist(for: stores.account.profile, count: nil) }
        return stores.library.playlists.value?.first { $0.id == id }
    }

    private func runDebugSwitch() async {
        #if DEBUG
        guard let id = debug.switchPlaylistID else { return }
        try? await Task.sleep(for: .seconds(2))
        guard let playlist = stores.library.playlists.value?.first(where: { $0.id == id }) else { return }
        await switcher.play(playlist, with: stores.playback, thenCollapse: nil)
        #endif
    }

    // Walks the sections and collapses on a timer, so transitions can be captured with no input. It expands only
    // when the launch did not: an expansion from the pill is a user opening Orbit, which makes the panel key.
    private func runDebugTour() async {
        #if DEBUG
        guard debug.runsTour else { return }
        let step = Duration.seconds(2.5)
        try? await Task.sleep(for: step)
        if !panel.isExpanded { expandFromPill() }
        for section in [PanelSection.library, .player] {
            try? await Task.sleep(for: step)
            withAnimation(resolvedTheme.animation(OrbitTokens.Motion.navigate)) { navigator.show(section) }
        }
        try? await Task.sleep(for: step)
        panel.collapse()
        #endif
    }

    private func seedDebugShelf() async {
        #if DEBUG
        guard debug.seedsShelf else { return }
        for _ in 0..<40 where stores.library.playlists.value == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let playlists = stores.library.playlists.value ?? []
        for id in ["pl-coding", "pl-synthwave", "pl-indie-pulse", "pl-gym"] {
            if let playlist = playlists.first(where: { $0.id == id }) { stores.library.recordRecent(playlist) }
        }
        for id in ["pl-gym", "pl-lofi-rain"] {
            if let playlist = playlists.first(where: { $0.id == id }) { stores.library.pin(playlist) }
        }
        #endif
    }

    private func openPendingDebugPlaylist() async {
        #if DEBUG
        if let id = pendingDebugPlaylistID {
            for _ in 0..<40 {
                if let playlist = debugPlaylist(id) {
                    navigator.push(.playlist(playlist))
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        #endif
    }
}
