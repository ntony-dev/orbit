import AppKit

// The app icon's mark, a body with a tilted orbit and a satellite, drawn as a template image so the menu bar tints
// it for light, dark and highlighted states.
enum OrbitGlyph {
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let ring = NSBezierPath(ovalIn: CGRect(x: -7.5, y: -3.6, width: 15, height: 7.2))
            var tilt = AffineTransform(translationByX: center.x, byY: center.y)
            tilt.rotate(byDegrees: 28)
            ring.transform(using: tilt)
            ring.lineWidth = 1.4
            ring.stroke()

            NSBezierPath(ovalIn: CGRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8)).fill()

            let satellite = tilt.transform(CGPoint(x: 7.5 * cos(.pi * 0.28), y: 3.6 * sin(.pi * 0.28)))
            NSBezierPath(ovalIn: CGRect(x: satellite.x - 1.7, y: satellite.y - 1.7, width: 3.4, height: 3.4)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Orbit"
        return image
    }
}
