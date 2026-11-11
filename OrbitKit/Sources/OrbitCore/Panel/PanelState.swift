import Observation

// Shared between OrbitUI and OrbitShell. Each property has one writer, noted beside it.
@MainActor
@Observable
public final class PanelState {
    // Written through expand() and collapse() by either side. The UI animates toward it; the shell reacts to it
    // (outside-click monitoring, Escape, giving up key status).
    public private(set) var isExpanded = false
    // Written by the shell whenever the pill settles somewhere new; never changes while expanded.
    public var anchor: PanelAnchor = .topLeading
    // Written by the shell for the duration of a drag.
    public var isDragging = false
    // Written by the shell: true while the panel is the key window and can receive typing.
    public var isKeyWindow = false

    public init() {}

    public func expand() {
        isExpanded = true
    }

    public func collapse() {
        isExpanded = false
    }
}
