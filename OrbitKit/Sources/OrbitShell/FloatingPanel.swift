import AppKit

// Borderless, non-activating, transparent canvas. Clicking it never activates Orbit, and it becomes key only when
// the UI asks for typing, so the user's frontmost app keeps keyboard focus during playback actions.
final class FloatingPanel: NSPanel {
    var acceptsKey = false
    var onCancel: (() -> Void)?
    // Where the current press started, so a drag that is recognised only after the movement threshold still
    // keeps the grabbed point under the cursor.
    private(set) var lastMouseDownLocation: NSPoint?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
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

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { lastMouseDownLocation = NSEvent.mouseLocation }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
