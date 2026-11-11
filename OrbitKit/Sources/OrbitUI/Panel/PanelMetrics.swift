import CoreGraphics
import OrbitCore

// The only geometry the shell needs to place the window: the pill the panel rests as, and the transparent margin
// the UI keeps around the glass. Every other size stays internal to OrbitUI.
public enum PanelMetrics {
    public static let canvasMargin: CGFloat = OrbitTokens.Size.canvasMargin

    public static func pillSize(_ size: PillSize) -> CGSize {
        OrbitTokens.Size.pill(size)
    }

    public static func canvas(for surface: CGSize) -> CGSize {
        CanvasPlan.canvas(for: surface)
    }
}
