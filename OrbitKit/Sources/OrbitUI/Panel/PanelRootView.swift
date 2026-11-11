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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(panel.anchor))
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
        .onChange(of: currentSurfaceSize) { _, size in
            fitCanvas(to: size)
        }
        .task(id: stores.playback.snapshot.track?.artworkURL) {
            await loadArtworkTint()
        }
        .task {
            await applyDebugScenario()
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
            artworkTint: artworkTint
        )
    }

    private var pillSize: CGSize {
        OrbitTokens.Size.pill(debug.pillSize ?? preferences.pillSize)
    }

    private var expandedSize: CGSize {
        var size = navigator.screenSize
        if navigator.section == .player, navigator.detail == nil,
           PlayerNoticeKind.current(account: stores.account, playback: stores.playback) != nil {
            size.height += PlayerNoticeKind.height
        }
        return size
    }

    private var currentSurfaceSize: CGSize {
        isShowingExpanded ? expandedSize : pillSize
    }

    // The pill fades out quickly so it never floats inside a growing card; the expanded content scales up from
    // the anchored corner as the surface reveals it. Reduced motion keeps only the fades.
    private func expandedTransition(_ theme: OrbitTheme) -> AnyTransition {
        let fadeIn = AnyTransition.opacity.animation(.easeOut(duration: 0.24).delay(0.08))
        let fadeOut = AnyTransition.opacity.animation(.easeIn(duration: 0.12))
        guard !theme.reducesMotion else { return .asymmetric(insertion: fadeIn, removal: fadeOut) }
        return .asymmetric(
            insertion: fadeIn.combined(with: .scale(scale: 0.94, anchor: UnitPoint(panel.anchor))),
            removal: fadeOut.combined(with: .scale(scale: 0.97, anchor: UnitPoint(panel.anchor)))
        )
    }

    private func pillTransition(_ theme: OrbitTheme) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(theme.reducesMotion ? 0 : 0.18)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }

    private func appear() {
        if panel.isExpanded {
            navigator.reset(to: panel.requestedDestination ?? .player)
            panel.clearRequestedDestination()
            applyDebugScreen()
            isShowingExpanded = true
        }
        allocatedCanvas = CanvasPlan.canvas(for: currentSurfaceSize)
        host.setCanvasSize(allocatedCanvas)
    }

    private func expandFromPill() {
        let isIdle = stores.playback.snapshot.track == nil && stores.account.authState.isSignedIn
        panel.expand(to: isIdle ? .playlistPicker : .player)
    }

    private func expand() {
        navigator.reset(to: panel.requestedDestination ?? .player)
        panel.clearRequestedDestination()
        withAnimation(resolvedTheme.animation(OrbitTokens.Motion.morph)) { isShowingExpanded = true }
    }

    private func collapse() {
        withAnimation(resolvedTheme.animation(OrbitTokens.Motion.morph)) { isShowingExpanded = false }
    }

    // Grows the canvas before the surface starts moving and shrinks it once the motion has settled. A newer
    // resize cancels an older pending shrink, so interrupted animations never clip the surface.
    private func fitCanvas(to surface: CGSize) {
        resizeGeneration += 1
        let generation = resizeGeneration
        let during = CanvasPlan.during(current: allocatedCanvas, target: surface)
        if during != allocatedCanvas {
            allocatedCanvas = during
            host.setCanvasSize(during)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(560))
            guard generation == resizeGeneration, let after = CanvasPlan.after(current: allocatedCanvas, target: surface) else { return }
            allocatedCanvas = after
            host.setCanvasSize(after)
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
        guard let screen = debug.screen else { return }
        switch screen {
        case "picker": navigator.show(.picker)
        case "library": navigator.showLibrary(.playlists)
        case "liked": navigator.showLibrary(.liked)
        case "queue": navigator.showLibrary(.queue)
        case "search": navigator.showLibrary(.search)
        case "devices": navigator.push(.devices)
        default:
            if screen.hasPrefix("playlist:") {
                let id = String(screen.dropFirst("playlist:".count))
                navigator.showLibrary(.playlists)
                if let playlist = stores.library.playlists.value?.first(where: { $0.id == id }) {
                    navigator.push(.playlist(playlist))
                } else {
                    pendingDebugPlaylistID = id
                }
            }
        }
    }

    @State private var pendingDebugPlaylistID: String?

    private func applyDebugScenario() async {
        #if DEBUG
        if let name = debug.scenario, let scenarioStores = await DebugScenarioStores.make(named: name) {
            stores = scenarioStores
        }
        if let id = pendingDebugPlaylistID {
            for _ in 0..<40 {
                if let playlist = stores.library.playlists.value?.first(where: { $0.id == id }) {
                    navigator.push(.playlist(playlist))
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        #endif
    }
}
