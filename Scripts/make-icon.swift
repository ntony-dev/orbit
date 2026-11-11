// Renders Orbit's app icon into an asset catalog icon set: a graphite squircle on the macOS icon grid holding a
// silver body, a tilted orbit and a satellite. Neutral on purpose; the album artwork brings the color.
// Usage: swift Scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
let canvas: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha]
    )!
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

// Squircle approximation of the macOS icon shape: 824pt body centred on a 1024pt canvas.
func iconShape() -> CGPath {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    return CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)
}

func drawIcon(in context: CGContext) {
    let shape = iconShape()
    let body = shape.boundingBox

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x1B1E23))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(
        gradient([(color(0x474D57), 0), (color(0x262A31), 0.55), (color(0x15171B), 1)]),
        start: CGPoint(x: body.midX, y: body.maxY),
        end: CGPoint(x: body.midX, y: body.minY),
        options: []
    )
    // A soft sheen across the top, as if the squircle were a pane of frosted glass.
    context.drawRadialGradient(
        gradient([(color(0xFFFFFF, 0.16), 0), (color(0xFFFFFF, 0), 1)]),
        startCenter: CGPoint(x: body.minX + body.width * 0.3, y: body.maxY - body.height * 0.12),
        startRadius: 0,
        endCenter: CGPoint(x: body.minX + body.width * 0.3, y: body.maxY - body.height * 0.12),
        endRadius: body.width * 0.75,
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.setStrokeColor(color(0xFFFFFF, 0.14))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    let center = CGPoint(x: body.midX, y: body.midY)
    let tilt = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: .pi * 28 / 180)
    let ring = CGRect(x: -320, y: -122, width: 640, height: 244)

    func strokeRing(from start: CGFloat, to end: CGFloat, alpha: CGFloat) {
        let path = CGMutablePath()
        var first = true
        for step in 0...180 {
            let angle = start + (end - start) * CGFloat(step) / 180
            let point = CGPoint(x: ring.midX + ring.width / 2 * cos(angle), y: ring.midY + ring.height / 2 * sin(angle)).applying(tilt)
            if first { path.move(to: point) } else { path.addLine(to: point) }
            first = false
        }
        context.saveGState()
        context.addPath(path)
        context.setLineCap(.round)
        context.setLineWidth(24)
        context.setStrokeColor(color(0xE9EDF2, alpha))
        context.strokePath()
        context.restoreGState()
    }

    // The far half of the orbit passes behind the body, the near half in front of it.
    strokeRing(from: 0, to: .pi, alpha: 0.92)

    let radius: CGFloat = 138
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.45))
    context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.setFillColor(color(0xC9CFD6))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.clip()
    let light = CGPoint(x: center.x - radius * 0.4, y: center.y + radius * 0.45)
    context.drawRadialGradient(
        gradient([(color(0xFFFFFF), 0), (color(0xDCE1E7), 0.35), (color(0x8E97A3), 1)]),
        startCenter: light,
        startRadius: 0,
        endCenter: light,
        endRadius: radius * 1.9,
        options: []
    )
    context.restoreGState()

    strokeRing(from: .pi, to: 2 * .pi, alpha: 0.92)

    let satelliteAngle = CGFloat.pi * 1.78
    let satellite = CGPoint(x: ring.width / 2 * cos(satelliteAngle), y: ring.height / 2 * sin(satelliteAngle)).applying(tilt)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 26, color: color(0xFFFFFF, 0.65))
    context.addEllipse(in: CGRect(x: satellite.x - 40, y: satellite.y - 40, width: 80, height: 80))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: context)
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(render(pixels: points * scale), to: outputDirectory.appendingPathComponent(name))
        entries.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#)
    }
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try! contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(entries.count) images to \(outputDirectory.path)")
