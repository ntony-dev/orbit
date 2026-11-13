import AppKit

// Borderless, non-activating, transparent canvas. Clicking it never activates Orbit. It can become key, and so
// receive typing, only while `acceptsKey` is set, which the controller does while Orbit is open for the user.
final class FloatingPanel: NSPanel {
    var acceptsKey = false
    var onCancel: (() -> Void)?
    var onMouseDown: (() -> Void)?
    // Where the current press started, so a drag that is recognised only after the movement threshold still
    // keeps the grabbed point under the cursor.
    private(set) var lastMouseDownLocation: NSPoint?

    init(contentRect: NSRect) {
        // The non-activating style only takes full effect when it is present at creation.
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own shadow; a window shadow would outline the whole transparent canvas.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    // macOS draws Liquid Glass in a frosted, inactive state in any window that is not key, which this panel is
    // while the pill is collapsed and after a click elsewhere, so Clear glass was only clear with keyboard focus.
    // AppKit asks the window this undocumented question to pick the state; should the hook ever go away, the glass
    // falls back to the system's behavior and nothing else changes.
    @objc(_hasActiveAppearance) private func hasActiveGlassAppearance() -> Bool { true }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    // Placement already keeps the glass inside the visible frame; AppKit would also push the transparent margin
    // below the menu bar, which left a docked pill lower than its edge gap.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            lastMouseDownLocation = NSEvent.mouseLocation
            onMouseDown?()
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
