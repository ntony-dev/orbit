import CoreGraphics
import OrbitCore
import SwiftUI

// The canvas must contain the surface for the whole animation. It grows to the union of the old and new
// surface before anything moves and shrinks to the new surface only once the animation has settled.
enum CanvasPlan {
    static func canvas(for surface: CGSize) -> CGSize {
        OrbitTokens.Size.canvas(for: surface)
    }

    // Canvas to apply right away when the surface heads for `target` while `current` is allocated.
    static func during(current: CGSize, target: CGSize) -> CGSize {
        let needed = canvas(for: target)
        return CGSize(width: max(current.width, needed.width), height: max(current.height, needed.height))
    }

    // Canvas to apply after settling, or nil when the canvas already fits.
    static func after(current: CGSize, target: CGSize) -> CGSize? {
        let needed = canvas(for: target)
        return current == needed ? nil : needed
    }

    // Where the root view lays the surface out in a canvas, in AppKit's orientation (origin bottom-left), so a
    // test can follow it on screen through PanelGeometry: aligned to the anchor, inset by the canvas margin.
    static func surfaceFrame(_ surface: CGSize, inCanvas canvas: CGSize, anchor: PanelAnchor) -> CGRect {
        let margin = OrbitTokens.Size.canvasMargin
        let room = CGSize(width: canvas.width - margin * 2, height: canvas.height - margin * 2)
        let unit = UnitPoint(anchor)
        return CGRect(
            x: margin + (room.width - surface.width) * unit.x,
            y: margin + (room.height - surface.height) * (1 - unit.y),
            width: surface.width,
            height: surface.height
        )
    }
}

extension Alignment {
    init(_ anchor: PanelAnchor) {
        switch (anchor.vertical, anchor.horizontal) {
        case (.top, .leading): self = .topLeading
        case (.top, .center): self = .top
        case (.top, .trailing): self = .topTrailing
        case (.center, .leading): self = .leading
        case (.center, .center): self = .center
        case (.center, .trailing): self = .trailing
        case (.bottom, .leading): self = .bottomLeading
        case (.bottom, .center): self = .bottom
        case (.bottom, .trailing): self = .bottomTrailing
        }
    }
}

// SwiftUI's orientation: y grows downward.
extension UnitPoint {
    init(_ anchor: PanelAnchor) {
        let x: CGFloat = switch anchor.horizontal {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let y: CGFloat = switch anchor.vertical {
        case .top: 0
        case .center: 0.5
        case .bottom: 1
        }
        self.init(x: x, y: y)
    }
}
