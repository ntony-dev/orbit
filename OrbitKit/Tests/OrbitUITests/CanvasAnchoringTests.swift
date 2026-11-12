import CoreGraphics
import OrbitCore
@testable import OrbitUI
import SwiftUI
import Testing

// Follows a whole expand and collapse on screen, the way the shell and the root view split it: the shell resizes
// the window around the anchor (PanelGeometry), and the UI lays the animating surface out in that canvas
// (CanvasPlan.surfaceFrame). The anchored corner or edge middle of the glass must never move.
struct CanvasAnchoringTests {
    let pill = OrbitTokens.Size.pill(.regular)
    let player = CGSize(width: 344, height: 318)
    let library = CGSize(width: 344, height: 488)

    // A spring with a little overshoot, as the morph uses, so the canvas must hold sizes past the target too.
    private func morph(from start: CGSize, to end: CGSize) -> [CGSize] {
        [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.04, 1.02, 1].map { t in
            CGSize(width: start.width + (end.width - start.width) * t, height: start.height + (end.height - start.height) * t)
        }
    }

    private func same(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001
    }

    private func surfaceOnScreen(_ surface: CGSize, canvas: CGRect, anchor: PanelAnchor) -> CGRect {
        CanvasPlan.surfaceFrame(surface, inCanvas: canvas.size, anchor: anchor).offsetBy(dx: canvas.minX, dy: canvas.minY)
    }

    @Test(arguments: PanelAnchor.all)
    func theAnchoredPointStaysPutThroughExpandAndCollapse(anchor: PanelAnchor) {
        var canvas = CGRect(origin: CGPoint(x: 1200, y: 600), size: CanvasPlan.canvas(for: pill))
        let fixed = PanelGeometry.point(of: surfaceOnScreen(pill, canvas: canvas, anchor: anchor), at: anchor)

        // Expanding: the canvas grows before the surface moves, and holds every size the surface passes through.
        let grown = CanvasPlan.during(current: canvas.size, target: player)
        #expect(grown == CanvasPlan.canvas(for: player))
        canvas = PanelGeometry.resize(canvas, to: grown, keeping: anchor)
        for size in morph(from: pill, to: player) {
            let surface = surfaceOnScreen(size, canvas: canvas, anchor: anchor)
            #expect(same(PanelGeometry.point(of: surface, at: anchor), fixed))
            #expect(canvas.insetBy(dx: -1, dy: -1).contains(surface))
        }
        #expect(CanvasPlan.after(current: canvas.size, target: player) == nil)

        // Collapsing: the canvas keeps its size until the surface has settled, then shrinks around the anchor.
        #expect(CanvasPlan.during(current: canvas.size, target: pill) == canvas.size)
        for size in morph(from: player, to: pill) {
            let surface = surfaceOnScreen(size, canvas: canvas, anchor: anchor)
            #expect(same(PanelGeometry.point(of: surface, at: anchor), fixed))
        }
        let shrunk = CanvasPlan.after(current: canvas.size, target: pill)
        #expect(shrunk == CanvasPlan.canvas(for: pill))
        canvas = PanelGeometry.resize(canvas, to: shrunk ?? canvas.size, keeping: anchor)
        #expect(same(PanelGeometry.point(of: surfaceOnScreen(pill, canvas: canvas, anchor: anchor), at: anchor), fixed))
    }

    @Test(arguments: PanelAnchor.all)
    func navigatingToATallerScreenKeepsTheAnchor(anchor: PanelAnchor) {
        var canvas = CGRect(origin: CGPoint(x: 900, y: 300), size: CanvasPlan.canvas(for: player))
        let fixed = PanelGeometry.point(of: surfaceOnScreen(player, canvas: canvas, anchor: anchor), at: anchor)
        canvas = PanelGeometry.resize(canvas, to: CanvasPlan.during(current: canvas.size, target: library), keeping: anchor)
        for size in morph(from: player, to: library) {
            #expect(same(PanelGeometry.point(of: surfaceOnScreen(size, canvas: canvas, anchor: anchor), at: anchor), fixed))
        }
    }

    // The owner's case: docked at the top centre, the card grows straight down and evenly to both sides, and its
    // top edge stays on the same screen row in every frame.
    @Test func aTopCentrePillGrowsStraightDown() {
        var canvas = CGRect(origin: CGPoint(x: 1584, y: 1336), size: CanvasPlan.canvas(for: pill))
        let start = surfaceOnScreen(pill, canvas: canvas, anchor: .topCenter)
        canvas = PanelGeometry.resize(canvas, to: CanvasPlan.during(current: canvas.size, target: player), keeping: .topCenter)
        for size in morph(from: pill, to: player) {
            let surface = surfaceOnScreen(size, canvas: canvas, anchor: .topCenter)
            #expect(abs(surface.maxY - start.maxY) < 0.001)
            #expect(abs(surface.midX - start.midX) < 0.001)
        }
    }

    @Test func alignmentAndUnitPointAgreeWithTheAnchor() {
        #expect(Alignment(.topCenter) == .top)
        #expect(Alignment(.bottomCenter) == .bottom)
        #expect(Alignment(.centerLeading) == .leading)
        #expect(Alignment(.centerTrailing) == .trailing)
        #expect(Alignment(.bottomTrailing) == .bottomTrailing)
        #expect(UnitPoint(.topCenter) == UnitPoint(x: 0.5, y: 0))
        #expect(UnitPoint(.centerTrailing) == UnitPoint(x: 1, y: 0.5))
        #expect(UnitPoint(.bottomLeading) == UnitPoint(x: 0, y: 1))
    }
}
