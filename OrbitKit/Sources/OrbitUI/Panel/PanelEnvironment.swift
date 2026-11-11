import OrbitCore
import OrbitEngine
import SwiftUI

extension EnvironmentValues {
    @Entry var panelHost: (any PanelHost)?
}

// Everything a panel view may read from its environment, injected in one place for the root view and tests.
struct PanelEnvironment: ViewModifier {
    let stores: OrbitStores
    let panel: PanelState
    let host: any PanelHost
    let preferences: Preferences
    let navigator: PanelNavigator
    let switcher: PlaylistSwitcher
    let theme: OrbitTheme

    func body(content: Content) -> some View {
        content
            .environment(\.orbitTheme, theme)
            .environment(\.panelHost, host)
            .environment(panel)
            .environment(preferences)
            .environment(navigator)
            .environment(switcher)
            .environment(stores.playback)
            .environment(stores.library)
            .environment(stores.account)
    }
}
