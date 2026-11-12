import Observation

// Where an expansion requested from outside the panel (menu bar, global shortcut) should land.
public enum PanelDestination: Hashable, Sendable {
    case player
    // The place to pick music: the library, from the top of its list.
    case playlistPicker
    // The library with its search field focused.
    case search
}

// Shared between OrbitUI and OrbitShell. Each property has one writer, noted beside it.
@MainActor
@Observable
public final class PanelState {
    // Written through expand() and collapse() by either side. The UI animates toward it; the shell reacts to it
    // (outside-click monitoring, Escape, giving up key status). Expanded does not imply key: an open panel stays
    // open while the user works in another app, unless they chose to collapse it on an outside click.
    public private(set) var isExpanded = false
    // Written by the shell whenever the pill settles somewhere new, and when the user drops a dragged open panel
    // while `isCanvasFitted`, which moves nothing on screen and only changes where the card collapses to.
    public var anchor: PanelAnchor = .topLeading
    // Written by the UI: true while the canvas is exactly the surface plus its margin and no resize is pending.
    public var isCanvasFitted = false
    // Written by the shell for the duration of a drag.
    public var isDragging = false
    // Written by the shell: true while the panel is the key window and can receive typing.
    public var isKeyWindow = false

    // Set by expand(to:). The UI navigates there and then calls clearRequestedDestination().
    public private(set) var requestedDestination: PanelDestination?
    // Written by the UI: how many layers (the library, a playlist, the device list or queue) sit above the player.
    public var openLayerCount = 0
    // Bumped by dismissActiveLayer() when a layer is open; the UI steps back one layer each time it changes.
    public private(set) var layerDismissals = 0

    public init() {}

    public func expand(to destination: PanelDestination = .player) {
        requestedDestination = destination
        isExpanded = true
    }

    public func clearRequestedDestination() {
        requestedDestination = nil
    }

    public func collapse() {
        isExpanded = false
    }

    // What Escape should do: close the active expanded layer, and collapse only from the player itself.
    public func dismissActiveLayer() {
        if isExpanded, openLayerCount > 0 {
            layerDismissals += 1
        } else {
            collapse()
        }
    }
}
