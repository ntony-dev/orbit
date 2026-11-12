import CoreGraphics
import OrbitCore
import Testing

struct PanelGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 870)

    @Test(arguments: [
        (CGPoint(x: 1300, y: 40), PanelAnchor.bottomTrailing),
        (CGPoint(x: 40, y: 40), PanelAnchor.bottomLeading),
        (CGPoint(x: 1300, y: 800), PanelAnchor.topTrailing),
        (CGPoint(x: 40, y: 800), PanelAnchor.topLeading),
    ])
    func anchorsTowardNearestCorner(origin: CGPoint, expected: PanelAnchor) {
        let canvas = CGRect(origin: origin, size: CGSize(width: 100, height: 40))
        #expect(PanelGeometry.anchor(forCanvas: canvas, in: screen) == expected)
    }

    @Test func bottomTrailingGrowsUpAndLeft() {
        let pill = CGRect(x: 1000, y: 50, width: 286, height: 84)
        let expanded = PanelGeometry.resize(pill, to: CGSize(width: 376, height: 466), keeping: .bottomTrailing)
        #expect(expanded.maxX == pill.maxX)
        #expect(expanded.minY == pill.minY)
        #expect(expanded.minX < pill.minX)
        #expect(expanded.maxY > pill.maxY)
    }

    @Test func topLeadingGrowsDownAndRight() {
        let pill = CGRect(x: 100, y: 700, width: 286, height: 84)
        let expanded = PanelGeometry.resize(pill, to: CGSize(width: 376, height: 466), keeping: .topLeading)
        #expect(expanded.minX == pill.minX)
        #expect(expanded.maxY == pill.maxY)
    }

    @Test func topCenterStaysCentred() {
        let pill = CGRect(x: 600, y: 780, width: 240, height: 80)
        let expanded = PanelGeometry.resize(pill, to: CGSize(width: 360, height: 400), keeping: .topCenter)
        #expect(expanded.midX == pill.midX)
        #expect(expanded.maxY == pill.maxY)
    }

    @Test func expandThenCollapseReturnsToTheSameFrame() {
        let pill = CGRect(x: 1000, y: 50, width: 286, height: 84)
        for anchor in PanelAnchor.all {
            let expanded = PanelGeometry.resize(pill, to: CGSize(width: 376, height: 466), keeping: anchor)
            #expect(PanelGeometry.resize(expanded, to: pill.size, keeping: anchor) == pill)
        }
    }

    @Test(arguments: PanelAnchor.all)
    func resizingKeepsTheAnchoredPointAndTheRequestedSize(anchor: PanelAnchor) {
        let pill = CGRect(x: 1584, y: 1336, width: 312, height: 92)
        for size in [CGSize(width: 384, height: 358), CGSize(width: 384, height: 528), CGSize(width: 252, height: 80)] {
            let resized = PanelGeometry.resize(pill, to: size, keeping: anchor)
            #expect(resized.size == size)
            #expect(PanelGeometry.point(of: resized, at: anchor) == PanelGeometry.point(of: pill, at: anchor))
        }
    }

    @Test func topCentreGrowsStraightDownWithItsTopEdgeFixed() {
        let pill = CGRect(x: 1584, y: 1336, width: 312, height: 92)
        let expanded = PanelGeometry.resize(pill, to: CGSize(width: 384, height: 358), keeping: .topCenter)
        #expect(expanded.maxY == pill.maxY)
        #expect(expanded.midX == pill.midX)
        #expect(expanded.minX == pill.minX - 36 && expanded.maxX == pill.maxX + 36)
    }

    @Test func sideMiddlesGrowInwardAndEvenlyAlongTheEdge() {
        let pill = CGRect(x: 3100, y: 600, width: 312, height: 92)
        let fromTrailing = PanelGeometry.resize(pill, to: CGSize(width: 384, height: 358), keeping: .centerTrailing)
        #expect(fromTrailing.maxX == pill.maxX && fromTrailing.midY == pill.midY)
        let fromLeading = PanelGeometry.resize(pill, to: CGSize(width: 384, height: 358), keeping: .centerLeading)
        #expect(fromLeading.minX == pill.minX && fromLeading.midY == pill.midY)
        let fromBottom = PanelGeometry.resize(pill, to: CGSize(width: 384, height: 358), keeping: .bottomCenter)
        #expect(fromBottom.minY == pill.minY && fromBottom.midX == pill.midX)
    }

    // An odd difference in size cannot be split evenly; the canvas keeps its exact size and a whole-point origin
    // rather than growing a point, so the UI's surface still lines up with the anchor.
    @Test func anOddDifferenceRoundsTheOriginNotTheSize() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 90)
        let resized = PanelGeometry.resize(frame, to: CGSize(width: 371, height: 300), keeping: .centerTrailing)
        #expect(resized.size == CGSize(width: 371, height: 300))
        #expect(resized.origin.y == resized.origin.y.rounded())
    }

    @Test func zeroSizeFrameBecomesTheAnchoredCorner() {
        let point = CGRect(x: 1400, y: 30, width: 0, height: 0)
        let pill = PanelGeometry.resize(point, to: CGSize(width: 286, height: 84), keeping: .bottomTrailing)
        #expect(pill.maxX == 1400 && pill.minY == 30)
    }

    @Test func dragKeepsThePressedPointUnderTheCursor() {
        let origin = PanelGeometry.dragOrigin(
            startOrigin: CGPoint(x: 100, y: 100),
            pressLocation: CGPoint(x: 150, y: 120),
            mouse: CGPoint(x: 400, y: 300)
        )
        #expect(origin == CGPoint(x: 350, y: 280))
    }

    @Test func smallMovementsStayClicks() {
        #expect(!PanelGeometry.exceedsDragThreshold(CGSize(width: 2, height: 2)))
        #expect(!PanelGeometry.exceedsDragThreshold(.zero))
        #expect(PanelGeometry.exceedsDragThreshold(CGSize(width: 4, height: 0)))
        #expect(PanelGeometry.exceedsDragThreshold(CGSize(width: -3, height: 3)))
    }
}
