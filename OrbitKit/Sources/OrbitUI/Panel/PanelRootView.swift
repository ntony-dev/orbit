import OrbitCore
import OrbitEngine
import SwiftUI

// Fills the shell's transparent canvas. The pill and the expanded card share one glass identity, so switching
// between them inside the container morphs the glass; the window itself never animates.
public struct PanelRootView: View {
    private let stores: OrbitStores
    private let panel: PanelState
    private let host: any PanelHost
    private let preferences: Preferences

    @Namespace private var glassNamespace
    @State private var isShowingCard = false
    @Environment(\.accessibilityReduceMotion) private var systemReducesMotion

    public init(stores: OrbitStores, panel: PanelState, host: any PanelHost, preferences: Preferences) {
        self.stores = stores
        self.panel = panel
        self.host = host
        self.preferences = preferences
    }

    public var body: some View {
        let accent = OrbitTokens.Palette.accent(preferences.accent)
        let glass = OrbitTokens.Material.glass(preferences.glassPreset, accent: accent)
        GlassEffectContainer {
            if isShowingCard {
                ExpandedCardView(stores: stores, panel: panel, host: host, preferences: preferences)
                    .glassEffect(glass, in: .rect(cornerRadius: OrbitTokens.Radius.card))
                    .glassEffectID(GlassID.surface, in: glassNamespace)
            } else {
                PillView(playback: stores.playback, preferences: preferences, onExpand: panel.expand)
                    .panelDragGesture(host)
                    .glassEffect(glass.interactive(), in: .capsule)
                    .glassEffectID(GlassID.surface, in: glassNamespace)
            }
        }
        .padding(OrbitTokens.Size.canvasMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(panel.anchor))
        .onAppear {
            // The panel may already be expanded before this view exists (the --expanded launch argument).
            isShowingCard = panel.isExpanded
            host.setCanvasSize(canvasSize(expanded: panel.isExpanded))
        }
        .onChange(of: panel.isExpanded) { _, expanded in
            let animation = OrbitTokens.Motion.morph(reduced: preferences.reducesAnimation || systemReducesMotion)
            if expanded {
                host.setCanvasSize(canvasSize(expanded: true))
                withAnimation(animation) { isShowingCard = true }
            } else {
                withAnimation(animation) {
                    isShowingCard = false
                } completion: {
                    if !panel.isExpanded { host.setCanvasSize(canvasSize(expanded: false)) }
                }
            }
        }
        .onChange(of: preferences.pillSize) {
            if !panel.isExpanded { host.setCanvasSize(canvasSize(expanded: false)) }
        }
    }

    private func canvasSize(expanded: Bool) -> CGSize {
        OrbitTokens.Size.canvas(for: expanded ? OrbitTokens.Size.expandedCard : OrbitTokens.Size.pill(preferences.pillSize))
    }

    private enum GlassID: Hashable {
        case surface
    }
}
