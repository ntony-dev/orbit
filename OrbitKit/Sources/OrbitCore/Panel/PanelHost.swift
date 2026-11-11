import CoreGraphics

// What the UI asks of the floating window. The window is a transparent canvas; the UI draws the pill and the
// expanded surface inside it and morphs between them itself, so the shell never animates the window frame.
@MainActor
public protocol PanelHost: AnyObject {
    // Resizes the canvas while keeping `PanelState.anchor` fixed on screen. The UI grows the canvas before an
    // expansion starts and shrinks it only after the collapse animation completes.
    func setCanvasSize(_ size: CGSize)

    // Drag the window from the UI's drag gesture. The shell tracks the global mouse location itself, so the
    // gesture's own translation, which shifts as the window moves, is never used.
    func beginDrag()
    func updateDrag()
    func endDrag()

    // Playback controls must never take keyboard focus from the user's frontmost app; the UI asks for key
    // status only while a text field needs typing, and gives it back when done.
    func setAcceptsKeyboardInput(_ accepts: Bool)
}
