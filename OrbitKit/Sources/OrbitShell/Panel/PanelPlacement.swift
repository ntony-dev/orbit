import CoreGraphics
import OrbitCore

// A display as placement sees it. `id` is the display UUID, which survives reconnects and resolution changes.
struct DisplayLayout: Equatable, Sendable {
    var id: String
    var visibleFrame: CGRect
}

struct PlacementOptions: Equatable, Sendable {
    var snapsToEdges: Bool
    var docksAtTopCenter: Bool
}

// Where the pill goes, in AppKit screen coordinates. Every function works on the glass surface (the pill or the
// expanded card), not the transparent canvas around it, so margins and snapping line up with what the user sees.
enum PanelPlacement {
    // Breathing room kept between the glass and the edge of the visible frame, for snapping and clamping alike,
    // so a snapped pill and a clamped pill sit in the same place.
    static let edgeGap: CGFloat = 8
    // How close the glass must come to a snap target before it sticks.
    static let snapDistance: CGFloat = 20

    // The display holding most of `surface`, else the nearest one, so a pill dragged into a gap between displays
    // or left on a display that shrank still belongs somewhere.
    static func display(for surface: CGRect, in displays: [DisplayLayout]) -> DisplayLayout? {
        let overlapping = displays
            .map { ($0, area($0.visibleFrame.intersection(surface))) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
        if let overlapping { return overlapping.0 }
        let center = CGPoint(x: surface.midX, y: surface.midY)
        return displays.min { distance(from: center, to: $0.visibleFrame) < distance(from: center, to: $1.visibleFrame) }
    }

    static func defaultSurface(size: CGSize, in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.maxX - edgeGap - size.width,
            y: visible.minY + edgeGap,
            width: size.width,
            height: size.height
        ).integral
    }

    static func dockedSurface(size: CGSize, in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - edgeGap - size.height,
            width: size.width,
            height: size.height
        ).integral
    }

    // Keeps the whole surface inside the visible frame. A surface larger than the frame is centred on it.
    static func clamp(_ surface: CGRect, to visible: CGRect) -> CGRect {
        let bounds = visible.insetBy(dx: edgeGap, dy: edgeGap)
        var clamped = surface
        clamped.origin.x = clampAxis(surface.minX, length: surface.width, min: bounds.minX, max: bounds.maxX)
        clamped.origin.y = clampAxis(surface.minY, length: surface.height, min: bounds.minY, max: bounds.maxY)
        return clamped.integral
    }

    // Magnetic snapping to the edges of the visible frame, and to the horizontal centre along the top and bottom
    // edges, which is how a free pill reaches the same spot as top-centre docking without turning docking on.
    static func snap(_ surface: CGRect, in visible: CGRect) -> CGRect {
        var snapped = surface
        let verticalTargets = [visible.minY + edgeGap, visible.maxY - edgeGap - surface.height]
        let snappedY = nearest(to: surface.minY, among: verticalTargets)
        if let snappedY { snapped.origin.y = snappedY }

        var horizontalTargets = [visible.minX + edgeGap, visible.maxX - edgeGap - surface.width]
        if snappedY != nil { horizontalTargets.append(visible.midX - surface.width / 2) }
        if let snappedX = nearest(to: surface.minX, among: horizontalTargets) { snapped.origin.x = snappedX }
        return snapped.integral
    }

    // Where a pill released or restored at `surface` comes to rest.
    static func settle(_ surface: CGRect, in visible: CGRect, options: PlacementOptions) -> CGRect {
        if options.docksAtTopCenter { return dockedSurface(size: surface.size, in: visible) }
        let clamped = clamp(surface, to: visible)
        return options.snapsToEdges ? snap(clamped, in: visible) : clamped
    }

    // The expanded surface grows away from the nearest corner so it stays on screen; a pill centred on the
    // display grows symmetrically.
    static func anchor(for surface: CGRect, in visible: CGRect) -> PanelAnchor {
        let horizontal: PanelAnchor.Horizontal =
            if abs(surface.midX - visible.midX) <= 1 { .center }
            else if surface.midX > visible.midX { .trailing }
            else { .leading }
        return PanelAnchor(horizontal: horizontal, vertical: surface.midY > visible.midY ? .top : .bottom)
    }

    static func savedPosition(of surface: CGRect, in visible: CGRect) -> SavedPanelPosition {
        SavedPanelPosition(
            x: Double((surface.midX - visible.minX) / max(visible.width, 1)),
            y: Double((surface.midY - visible.minY) / max(visible.height, 1))
        )
    }

    static func surface(size: CGSize, at position: SavedPanelPosition, in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.minX + CGFloat(position.x) * visible.width - size.width / 2,
            y: visible.minY + CGFloat(position.y) * visible.height - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    // The pill's resting place at launch or after the display arrangement changes: the remembered spot on the
    // display the user chose, or, while that display is disconnected, the first display (the one with the menu
    // bar). Offscreen or out-of-date positions are pulled back inside the visible frame.
    static func restore(
        size: CGSize,
        saved: [String: SavedPanelPosition],
        preferredDisplayID: String?,
        displays: [DisplayLayout],
        options: PlacementOptions
    ) -> (surface: CGRect, display: DisplayLayout)? {
        guard let display = displays.first(where: { $0.id == preferredDisplayID }) ?? displays.first else { return nil }
        let visible = display.visibleFrame
        let surface = saved[display.id].map { self.surface(size: size, at: $0, in: visible) }
            ?? defaultSurface(size: size, in: visible)
        return (settle(surface, in: visible, options: options), display)
    }

    private static func nearest(to value: CGFloat, among targets: [CGFloat]) -> CGFloat? {
        targets
            .filter { abs($0 - value) <= snapDistance }
            .min { abs($0 - value) < abs($1 - value) }
    }

    private static func clampAxis(_ origin: CGFloat, length: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        guard length <= upper - lower else { return (lower + upper - length) / 2 }
        return Swift.min(Swift.max(origin, lower), upper - length)
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = Swift.max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = Swift.max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
