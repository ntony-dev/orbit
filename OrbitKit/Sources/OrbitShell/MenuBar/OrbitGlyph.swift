import AppKit

// The app icon's mark, the pill with its album square and play triangle inside a tilted orbit and a satellite,
// drawn as a template image so the menu bar tints it for light, dark and highlighted states. Geometry is in the
// coordinates of `Design/orbit-symbol.svg`. A template has one color, so depth is shown with gaps: the ring is cut
// where it passes behind the pill, and the pill is cut where the ring passes in front.
enum OrbitGlyph {
    private static let artBounds = CGRect(x: 130, y: 216, width: 764, height: 538)
    private static let height: CGFloat = 17

    static func menuBarImage() -> NSImage {
        let scale = height / artBounds.height
        let size = NSSize(width: (artBounds.width * scale).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: (rect.width - artBounds.width * scale) / 2, y: 0)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -artBounds.minX, y: -artBounds.minY)
            draw(in: context, gap: 0.8 / scale)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orbit"
        return image
    }

    private static func draw(in context: CGContext, gap: CGFloat) {
        let ringWidth: CGFloat = 50
        let pill = CGRect(x: 172, y: 382, width: 680, height: 260)
        let pillPath = CGPath(roundedRect: pill, cornerWidth: 130, cornerHeight: 130, transform: nil)
        let pillHalo = pill.insetBy(dx: -gap, dy: -gap)
        let pillHaloPath = CGPath(
            roundedRect: pillHalo, cornerWidth: pillHalo.height / 2, cornerHeight: pillHalo.height / 2, transform: nil
        )
        let satellite = CGRect(x: 705.62, y: 276.43, width: 0, height: 0).insetBy(dx: -58, dy: -58)

        context.setFillColor(.black)
        context.setStrokeColor(.black)
        context.setLineWidth(ringWidth)

        context.addPath(ringArc(from: 0, to: 2 * .pi))
        context.strokePath()

        context.setBlendMode(.clear)
        context.addPath(pillHaloPath)
        context.fillPath()

        context.setBlendMode(.normal)
        context.addPath(pillPath)
        context.fillPath()

        context.setBlendMode(.clear)
        context.addPath(CGPath(
            roundedRect: CGRect(x: 248, y: 440, width: 144, height: 144), cornerWidth: 36, cornerHeight: 36, transform: nil
        ))
        context.fillPath()
        context.move(to: CGPoint(x: 560, y: 462))
        context.addLine(to: CGPoint(x: 646, y: 512))
        context.addLine(to: CGPoint(x: 560, y: 562))
        context.closePath()
        context.fillPath()

        // The lower half of the ring passes in front of the pill.
        context.saveGState()
        context.addPath(pillHaloPath)
        context.clip()
        context.setLineWidth(ringWidth + 2 * gap)
        context.addPath(ringArc(from: 0, to: .pi))
        context.strokePath()
        context.restoreGState()

        context.setBlendMode(.normal)
        context.addPath(ringArc(from: 0, to: .pi))
        context.strokePath()

        context.setBlendMode(.clear)
        context.fillEllipse(in: satellite.insetBy(dx: -gap, dy: -gap))
        context.setBlendMode(.normal)
        context.fillEllipse(in: satellite)
    }

    private static func ringArc(from start: CGFloat, to end: CGFloat) -> CGPath {
        let ellipse = CGAffineTransform(translationX: 512, y: 500).rotated(by: -20 * .pi / 180).scaledBy(x: 372, y: 200)
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: 1, startAngle: start, endAngle: end, clockwise: false, transform: ellipse)
        return path
    }
}
