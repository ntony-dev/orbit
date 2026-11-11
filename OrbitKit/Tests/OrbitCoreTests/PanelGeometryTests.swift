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
        for anchor in [PanelAnchor.bottomTrailing, .bottomLeading, .topTrailing, .topLeading, .topCenter] {
            let expanded = PanelGeometry.resize(pill, to: CGSize(width: 376, height: 466), keeping: anchor)
            #expect(PanelGeometry.resize(expanded, to: pill.size, keeping: anchor) == pill)
        }
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
