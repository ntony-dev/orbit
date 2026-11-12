import CoreGraphics
import OrbitCore
@testable import OrbitShell
import Testing

struct PanelPlacementTests {
    // The primary user's setup: one 3440x1440 display, no notch, menu bar 24pt, Dock at the bottom.
    private let ultrawide = DisplayLayout(id: "ultrawide", visibleFrame: CGRect(x: 0, y: 70, width: 3440, height: 1346))
    // A Retina laptop to the left of it, at a different scale factor and lower origin.
    private let laptop = DisplayLayout(id: "laptop", visibleFrame: CGRect(x: -1512, y: -200, width: 1512, height: 920))
    private let pill = CGSize(width: 250, height: 48)
    private let free = PlacementOptions(snapsToEdges: false, docksAtTopCenter: false)
    private let snapping = PlacementOptions(snapsToEdges: true, docksAtTopCenter: false)
    private let docking = PlacementOptions(snapsToEdges: true, docksAtTopCenter: true)

    @Test func defaultPositionIsInsideTheBottomTrailingCorner() {
        let surface = PanelPlacement.defaultSurface(size: pill, in: ultrawide.visibleFrame)
        #expect(surface.maxX == ultrawide.visibleFrame.maxX - PanelPlacement.edgeGap)
        #expect(surface.minY == ultrawide.visibleFrame.minY + PanelPlacement.edgeGap)
    }

    @Test func dockingCentresUnderTheTopEdge() {
        let surface = PanelPlacement.dockedSurface(size: pill, in: ultrawide.visibleFrame)
        #expect(surface.midX == ultrawide.visibleFrame.midX)
        #expect(surface.maxY == ultrawide.visibleFrame.maxY - PanelPlacement.edgeGap)
        #expect(PanelPlacement.anchor(for: surface, in: ultrawide.visibleFrame) == .topCenter)
    }

    @Test func clampingPullsAnOffscreenPillBackInside() {
        let offscreen = CGRect(origin: CGPoint(x: 5000, y: -400), size: pill)
        let clamped = PanelPlacement.clamp(offscreen, to: ultrawide.visibleFrame)
        #expect(ultrawide.visibleFrame.insetBy(dx: PanelPlacement.edgeGap, dy: PanelPlacement.edgeGap).contains(clamped))
        #expect(clamped.size == pill)
    }

    @Test func clampingLeavesAnOnscreenPillAlone() {
        let surface = CGRect(origin: CGPoint(x: 1200, y: 600), size: pill)
        #expect(PanelPlacement.clamp(surface, to: ultrawide.visibleFrame) == surface)
    }

    @Test func clampingCentresASurfaceLargerThanTheDisplay() {
        let tiny = CGRect(x: 0, y: 0, width: 200, height: 300)
        let clamped = PanelPlacement.clamp(CGRect(origin: .zero, size: pill), to: tiny)
        #expect(clamped.midX == tiny.midX)
    }

    @Test func snapsToANearbyEdge() {
        let nearRight = CGRect(origin: CGPoint(x: ultrawide.visibleFrame.maxX - pill.width - 20, y: 600), size: pill)
        let snapped = PanelPlacement.snap(nearRight, in: ultrawide.visibleFrame)
        #expect(snapped.maxX == ultrawide.visibleFrame.maxX - PanelPlacement.edgeGap)
        #expect(snapped.minY == 600)
    }

    @Test func doesNotSnapFromFarAway() {
        let middle = CGRect(origin: CGPoint(x: 1500, y: 600), size: pill)
        #expect(PanelPlacement.snap(middle, in: ultrawide.visibleFrame) == middle)
    }

    @Test func snapsToTheTopCentreOnlyAlongTheTopEdge() {
        let visible = ultrawide.visibleFrame
        let nearTopCentre = CGRect(origin: CGPoint(x: visible.midX - pill.width / 2 + 12, y: visible.maxY - pill.height - 14), size: pill)
        let snapped = PanelPlacement.snap(nearTopCentre, in: visible)
        #expect(snapped.midX == visible.midX)
        #expect(snapped.maxY == visible.maxY - PanelPlacement.edgeGap)

        let nearCentreMidScreen = CGRect(origin: CGPoint(x: visible.midX - pill.width / 2 + 12, y: 600), size: pill)
        #expect(PanelPlacement.snap(nearCentreMidScreen, in: visible) == nearCentreMidScreen)
    }

    @Test func snapsIntoACorner() {
        let visible = ultrawide.visibleFrame
        let nearCorner = CGRect(origin: CGPoint(x: visible.minX + 15, y: visible.minY + 3), size: pill)
        let snapped = PanelPlacement.snap(nearCorner, in: visible)
        #expect(snapped.origin == CGPoint(x: visible.minX + PanelPlacement.edgeGap, y: visible.minY + PanelPlacement.edgeGap))
    }

    @Test func settlingHonoursEachMode() {
        let visible = ultrawide.visibleFrame
        let nearLeft = CGRect(origin: CGPoint(x: visible.minX + 18, y: 700), size: pill)
        #expect(PanelPlacement.settle(nearLeft, in: visible, options: free) == nearLeft)
        #expect(PanelPlacement.settle(nearLeft, in: visible, options: snapping).minX == visible.minX + PanelPlacement.edgeGap)
        #expect(PanelPlacement.settle(nearLeft, in: visible, options: docking) == PanelPlacement.dockedSurface(size: pill, in: visible))
    }

    @Test(arguments: [
        (CGPoint(x: 3000, y: 100), PanelAnchor.bottomTrailing),
        (CGPoint(x: 100, y: 100), PanelAnchor.bottomLeading),
        (CGPoint(x: 3000, y: 1300), PanelAnchor.topTrailing),
        (CGPoint(x: 100, y: 1300), PanelAnchor.topLeading),
    ])
    func anchorsTowardTheNearestCorner(origin: CGPoint, expected: PanelAnchor) {
        #expect(PanelPlacement.anchor(for: CGRect(origin: origin, size: pill), in: ultrawide.visibleFrame) == expected)
    }

    @Test func aDockedOrTopSnappedPillGrowsFromTheTopEdge() {
        let visible = ultrawide.visibleFrame
        #expect(PanelPlacement.anchor(for: PanelPlacement.dockedSurface(size: pill, in: visible), in: visible) == .topCenter)
        let nearTopCentre = CGRect(origin: CGPoint(x: visible.midX - pill.width / 2 + 12, y: visible.maxY - pill.height - 14), size: pill)
        let snapped = PanelPlacement.snap(nearTopCentre, in: visible)
        #expect(PanelPlacement.anchor(for: snapped, in: visible) == .topCenter)
    }

    // Dropped near, not exactly at, the middle of an edge: it still grows from that edge, never from a corner.
    @Test(arguments: [
        (CGPoint(x: 1895, y: 1338), PanelAnchor.topCenter),
        (CGPoint(x: 1195, y: 78), PanelAnchor.bottomCenter),
        (CGPoint(x: 8, y: 819), PanelAnchor.centerLeading),
        (CGPoint(x: 3182, y: 569), PanelAnchor.centerTrailing),
    ])
    func aPillNearTheMiddleOfAnEdgeGrowsFromThatEdge(origin: CGPoint, expected: PanelAnchor) {
        #expect(PanelPlacement.anchor(for: CGRect(origin: origin, size: pill), in: ultrawide.visibleFrame) == expected)
    }

    @Test func outsideTheMiddleThirdOfAnEdgeItGrowsFromTheCorner() {
        let visible = ultrawide.visibleFrame
        let topRightThird = CGRect(x: 2700, y: visible.maxY - PanelPlacement.edgeGap - pill.height, width: pill.width, height: pill.height)
        #expect(PanelPlacement.anchor(for: topRightThird, in: visible) == .topTrailing)
        let floatingNearTheMiddle = CGRect(x: visible.midX - pill.width / 2 + 40, y: 900, width: pill.width, height: pill.height)
        #expect(PanelPlacement.anchor(for: floatingNearTheMiddle, in: visible) == .topTrailing)
    }

    @Test func aPillInTheCornerOfTwoEdgesGrowsFromTheCorner() {
        let visible = ultrawide.visibleFrame
        let snapped = PanelPlacement.snap(CGRect(x: 3175, y: 80, width: pill.width, height: pill.height), in: visible)
        #expect(PanelPlacement.anchor(for: snapped, in: visible) == .bottomTrailing)
    }

    @Test func savedPositionRoundTrips() {
        let surface = CGRect(origin: CGPoint(x: 900, y: 333), size: pill)
        let saved = PanelPlacement.savedPosition(of: surface, in: ultrawide.visibleFrame)
        #expect(PanelPlacement.surface(size: pill, at: saved, in: ultrawide.visibleFrame) == surface)
    }

    @Test func positionScalesWithAResolutionChange() {
        let before = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let after = CGRect(x: 0, y: 0, width: 2560, height: 1080)
        let surface = CGRect(origin: CGPoint(x: 1595, y: 696), size: pill)
        let saved = PanelPlacement.savedPosition(of: surface, in: before)
        let restored = PanelPlacement.surface(size: pill, at: saved, in: after)
        #expect(abs(restored.midX - after.midX) <= 1)
        #expect(abs(restored.midY - after.midY) <= 1)
    }

    @Test func edgeSnappedPillStaysOnTheEdgeAtASmallerResolution() {
        let before = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let after = DisplayLayout(id: "ultrawide", visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let snapped = PanelPlacement.settle(CGRect(origin: CGPoint(x: 3180, y: 600), size: pill), in: before, options: snapping)
        let restored = PanelPlacement.restore(
            size: pill,
            saved: ["ultrawide": PanelPlacement.savedPosition(of: snapped, in: before)],
            preferredDisplayID: "ultrawide",
            displays: [after],
            options: snapping
        )
        #expect(restored?.surface.maxX == after.visibleFrame.maxX - PanelPlacement.edgeGap)
    }

    @Test func restoresOnTheRememberedDisplay() {
        let saved = ["laptop": SavedPanelPosition(x: 0.25, y: 0.5)]
        let restored = PanelPlacement.restore(size: pill, saved: saved, preferredDisplayID: "laptop", displays: [ultrawide, laptop], options: free)
        #expect(restored?.display == laptop)
        #expect(restored.map { laptop.visibleFrame.contains($0.surface) } == true)
    }

    @Test func fallsBackToTheMainDisplayWhileTheRememberedOneIsDisconnected() {
        let saved = ["laptop": SavedPanelPosition(x: 0.25, y: 0.5)]
        let restored = PanelPlacement.restore(size: pill, saved: saved, preferredDisplayID: "laptop", displays: [ultrawide], options: free)
        #expect(restored?.display == ultrawide)
        #expect(restored?.surface == PanelPlacement.defaultSurface(size: pill, in: ultrawide.visibleFrame))
    }

    @Test func recoversASavedPositionThatIsNowOffscreen() {
        let saved = ["ultrawide": SavedPanelPosition(x: 1.4, y: -0.3)]
        let restored = PanelPlacement.restore(size: pill, saved: saved, preferredDisplayID: "ultrawide", displays: [ultrawide], options: free)
        let inner = ultrawide.visibleFrame.insetBy(dx: PanelPlacement.edgeGap, dy: PanelPlacement.edgeGap)
        #expect(restored.map { inner.contains($0.surface) } == true)
    }

    @Test func restoresNothingWithoutDisplays() {
        #expect(PanelPlacement.restore(size: pill, saved: [:], preferredDisplayID: nil, displays: [], options: free) == nil)
    }

    @Test func displayIsTheOneHoldingMostOfThePill() {
        let straddling = CGRect(x: -100, y: 400, width: 250, height: 48)
        #expect(PanelPlacement.display(for: straddling, in: [ultrawide, laptop]) == ultrawide)
        let mostlyLaptop = CGRect(x: -200, y: 400, width: 250, height: 48)
        #expect(PanelPlacement.display(for: mostlyLaptop, in: [ultrawide, laptop]) == laptop)
    }

    @Test func displayForAPillInAGapIsTheNearestOne() {
        let belowLaptop = CGRect(x: -800, y: -600, width: 250, height: 48)
        #expect(PanelPlacement.display(for: belowLaptop, in: [ultrawide, laptop]) == laptop)
    }
}
