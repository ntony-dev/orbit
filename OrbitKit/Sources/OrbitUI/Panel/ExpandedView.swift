import OrbitCore
import OrbitEngine
import SwiftUI

// The expanded surface: the active screen above a persistent section switcher. Screens slide a short distance
// in the direction of travel while cross-fading, so the way back is always the way you came.
struct ExpandedView: View {
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        @Bindable var navigator = navigator
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                screen
                    .id(ScreenID(section: navigator.section, detail: navigator.detail))
                    .transition(screenTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            SegmentedControl(
                segments: [
                    Segment(value: PanelSection.player, title: "Now Playing", symbol: "play.circle"),
                    Segment(value: PanelSection.picker, title: "Playlists", symbol: "music.note.list"),
                    Segment(value: PanelSection.library, title: "Library", symbol: "square.stack"),
                ],
                selection: Binding(
                    get: { navigator.section },
                    set: { navigator.show($0) }
                )
            )
            .padding(.horizontal, OrbitTokens.Spacing.l)
            .padding(.top, OrbitTokens.Spacing.s)
            .padding(.bottom, OrbitTokens.Spacing.l)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch (navigator.detail, navigator.section) {
        case (.playlist(let playlist), _): PlaylistDetailView(playlist: playlist)
        case (.devices, _): DeviceListView()
        case (nil, .player): PlayerView()
        case (nil, .picker): QuickPickerView()
        case (nil, .library): LibraryView()
        }
    }

    private struct ScreenID: Hashable {
        let section: PanelSection
        let detail: PanelDetail?
    }

    // The outgoing screen clears out faster than the incoming one arrives, so the two never read as a double
    // exposure in the middle of the move.
    private var screenTransition: AnyTransition {
        let fadeOut = AnyTransition.opacity.animation(theme.animation(OrbitTokens.Motion.screenFadeOut))
        guard !theme.reducesMotion else { return .asymmetric(insertion: .opacity, removal: fadeOut) }
        let offset = OrbitTokens.Motion.navigationOffset
        let incoming = AnyTransition.offset(x: navigator.isForward ? offset : -offset).combined(with: .opacity)
        let outgoing = AnyTransition.offset(x: navigator.isForward ? -offset : offset).combined(with: fadeOut)
        return .asymmetric(insertion: incoming, removal: outgoing)
    }
}
