import CoreGraphics

// Pure window math behind the panel seam, in AppKit screen coordinates (origin bottom-left, y up), so it can be
// unit tested without a window.
public enum PanelGeometry {
    // Pointer travel before a press on the pill becomes a drag instead of a click.
    public static let dragThreshold: CGFloat = 4

    public static func exceedsDragThreshold(_ translation: CGSize) -> Bool {
        (translation.width * translation.width + translation.height * translation.height) >= dragThreshold * dragThreshold
    }

    // The nearest screen corner, which the expanded surface grows away from so it stays on screen.
    public static func anchor(forCanvas canvas: CGRect, in visibleFrame: CGRect) -> PanelAnchor {
        PanelAnchor(
            horizontal: canvas.midX > visibleFrame.midX ? .trailing : .leading,
            vertical: canvas.midY > visibleFrame.midY ? .top : .bottom
        )
    }

    // The new canvas frame for `size`, keeping the anchored corner or edge middle where it was. Only the origin is
    // rounded, so the canvas is always exactly the size the UI asked for and its surface lines up with the anchor.
    public static func resize(_ frame: CGRect, to size: CGSize, keeping anchor: PanelAnchor) -> CGRect {
        let fixed = point(of: frame, at: anchor)
        let unit = unitPoint(of: anchor)
        return CGRect(
            x: (fixed.x - size.width * unit.x).rounded(),
            y: (fixed.y - size.height * unit.y).rounded(),
            width: size.width,
            height: size.height
        )
    }

    // The anchored point of `frame` in screen coordinates: what stays put while the canvas resizes.
    public static func point(of frame: CGRect, at anchor: PanelAnchor) -> CGPoint {
        let unit = unitPoint(of: anchor)
        return CGPoint(x: frame.minX + frame.width * unit.x, y: frame.minY + frame.height * unit.y)
    }

    // Where the anchor sits in a frame, from its bottom-left corner (AppKit's y points up).
    private static func unitPoint(of anchor: PanelAnchor) -> (x: CGFloat, y: CGFloat) {
        let x: CGFloat = switch anchor.horizontal {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let y: CGFloat = switch anchor.vertical {
        case .top: 1
        case .center: 0.5
        case .bottom: 0
        }
        return (x, y)
    }

    // Window origin during a drag, from global mouse positions only. `pressLocation` is where the press began,
    // not where the drag was recognised, so the grabbed point stays under the cursor.
    public static func dragOrigin(startOrigin: CGPoint, pressLocation: CGPoint, mouse: CGPoint) -> CGPoint {
        CGPoint(x: startOrigin.x + mouse.x - pressLocation.x, y: startOrigin.y + mouse.y - pressLocation.y)
    }
}
