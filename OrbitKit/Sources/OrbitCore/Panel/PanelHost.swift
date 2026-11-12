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

    // The shell makes the panel key whenever the user opens it, and hands key status back to the user's app when
    // it collapses or the user turns to another app, which by default leaves it open; the collapsed pill never
    // takes key, so its playback controls leave focus where it was. Asking for true makes an open but unfocused
    // panel key (a click into a search field). False is ignored while expanded, so Escape still reaches Orbit after
    // a field gives up focus.
    func setAcceptsKeyboardInput(_ accepts: Bool)
}
