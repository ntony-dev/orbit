import CoreGraphics

// Pure window math behind the panel seam, in AppKit screen coordinates (origin bottom-left, y up), so it can be
// unit tested without a window.
public enum PanelGeometry {
    // Pointer travel before a press on the pill becomes a drag instead of a click.
    public static let dragThreshold: CGFloat = 4

    public static func exceedsDragThreshold(_ translation: CGSize) -> Bool {
        (translation.width * translation.width + translation.height * translation.height) >= dragThreshold * dragThreshold
    }

    // The pill grows away from the nearest screen corner, so the expanded surface stays on screen.
    public static func anchor(forCanvas canvas: CGRect, in visibleFrame: CGRect) -> PanelAnchor {
        PanelAnchor(
            horizontal: canvas.midX > visibleFrame.midX ? .trailing : .leading,
            vertical: canvas.midY > visibleFrame.midY ? .top : .bottom
        )
    }

    // The new canvas frame for `size`, keeping the anchored corner (or top/bottom centre) where it was.
    public static func resize(_ frame: CGRect, to size: CGSize, keeping anchor: PanelAnchor) -> CGRect {
        var resized = CGRect(origin: frame.origin, size: size)
        switch anchor.horizontal {
        case .leading: resized.origin.x = frame.minX
        case .center: resized.origin.x = frame.midX - size.width / 2
        case .trailing: resized.origin.x = frame.maxX - size.width
        }
        switch anchor.vertical {
        case .top: resized.origin.y = frame.maxY - size.height
        case .bottom: resized.origin.y = frame.minY
        }
        return resized.integral
    }

    // Window origin during a drag, from global mouse positions only. `pressLocation` is where the press began,
    // not where the drag was recognised, so the grabbed point stays under the cursor.
    public static func dragOrigin(startOrigin: CGPoint, pressLocation: CGPoint, mouse: CGPoint) -> CGPoint {
        CGPoint(x: startOrigin.x + mouse.x - pressLocation.x, y: startOrigin.y + mouse.y - pressLocation.y)
    }
}
