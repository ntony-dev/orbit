// Composes README screenshots: each panel is cut out of a capture taken over the debug "plain" backdrop, using
// the alpha of a second capture taken with no backdrop (where everything outside the panel is transparent), and
// the cut-outs are laid out on one large wallpaper with a window shadow, so panels of different heights read as
// windows on one desktop instead of a staggered grid of tiles.
// Usage: swift Scripts/compose-readme-image.swift output.png --scale N --column shot[,shot...] [--column ...]
//   where each shot is backdrop.png:mask.png. A column stacks its panels; columns sit side by side, centered.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Layout {
    static let padding: CGFloat = 56
    static let columnGap: CGFloat = 48
    static let rowGap: CGFloat = 28
    static let cornerRadius: CGFloat = 28
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    return image
}

func rgbaContext(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("cannot allocate a \(width)x\(height) image") }
    return context
}

// The panel cut out of the backdrop capture, cropped to the panel's own bounds.
func cutOut(backdropPath: String, maskPath: String) -> CGImage {
    let backdrop = load(backdropPath)
    let maskSource = load(maskPath)
    guard backdrop.width == maskSource.width, backdrop.height == maskSource.height else {
        fail("\(backdropPath) and \(maskPath) differ in size, so the panel moved between the two captures")
    }
    let width = backdrop.width, height = backdrop.height
    var alpha = [UInt8](repeating: 0, count: width * height)
    alpha.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        )!
        context.draw(maskSource, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    // Rows in the buffer run top to bottom, like the image.
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where alpha[y * width + x] > 8 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { fail("\(maskPath) has no opaque panel to cut out") }
    let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    let mask = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: CGDataProvider(data: Data(alpha) as CFData)!, decode: nil, shouldInterpolate: false,
        intent: .defaultIntent
    )!.cropping(to: crop)!
    let context = rgbaContext(width: Int(crop.width), height: Int(crop.height))
    let bounds = CGRect(origin: .zero, size: crop.size)
    context.clip(to: bounds, mask: mask)
    context.draw(backdrop.cropping(to: crop)!, in: bounds)
    return context.makeImage()!
}

// The debug backdrop's "plain" dark wallpaper (DebugBackdrop.plain in OrbitUI), drawn at the composite's size so
// the glass in each cut-out still matches what is around it.
func drawWallpaper(in context: CGContext, size: CGSize) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
    let base = CGGradient(colorsSpace: space, colors: [color(0.13, 0.16, 0.27), color(0.20, 0.17, 0.30), color(0.08, 0.18, 0.22)] as CFArray, locations: [0, 0.5, 1])!
    // Core Graphics puts the origin at the bottom left, so SwiftUI's top leading is (0, height).
    context.drawLinearGradient(base, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
    let radius = max(size.width, size.height) * 0.75
    let glows: [(CGFloat, CGFloat, CGFloat, CGPoint)] = [
        (0.36, 0.30, 0.62, CGPoint(x: 0, y: size.height)),
        (0.14, 0.42, 0.48, CGPoint(x: size.width, y: 0)),
        (0.52, 0.28, 0.40, CGPoint(x: size.width, y: size.height / 2)),
    ]
    for (r, g, b, center) in glows {
        let glow = CGGradient(colorsSpace: space, colors: [color(r, g, b, 0.85), color(r, g, b, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else { fail("usage: compose-readme-image.swift output.png --scale N --column a.png:a-mask.png[,...] ...") }
let output = arguments.removeFirst()
var scale: CGFloat = 1
var columns: [[CGImage]] = []
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard let value = arguments.first else { fail("\(flag) needs a value") }
    arguments.removeFirst()
    switch flag {
    case "--scale":
        guard let parsed = Double(value), parsed > 0 else { fail("--scale needs a positive number") }
        scale = CGFloat(parsed)
    case "--column":
        columns.append(value.split(separator: ",").map { shot in
            let parts = shot.split(separator: ":").map(String.init)
            guard parts.count == 2 else { fail("each shot is backdrop.png:mask.png, not \(shot)") }
            return cutOut(backdropPath: parts[0], maskPath: parts[1])
        })
    default:
        fail("unknown option \(flag)")
    }
}
guard !columns.isEmpty else { fail("no --column given") }

let padding = Layout.padding * scale, columnGap = Layout.columnGap * scale, rowGap = Layout.rowGap * scale
let columnSizes = columns.map { panels in
    CGSize(
        width: CGFloat(panels.map(\.width).max()!),
        height: CGFloat(panels.map(\.height).reduce(0, +)) + rowGap * CGFloat(panels.count - 1)
    )
}
let contentHeight = columnSizes.map(\.height).max()!
let size = CGSize(
    width: (padding * 2 + columnSizes.map(\.width).reduce(0, +) + columnGap * CGFloat(columns.count - 1)).rounded(),
    height: (padding * 2 + contentHeight).rounded()
)
let context = rgbaContext(width: Int(size.width), height: Int(size.height))
let card = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: Layout.cornerRadius * scale, cornerHeight: Layout.cornerRadius * scale, transform: nil)
context.addPath(card)
context.clip()
drawWallpaper(in: context, size: size)
context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 40 * scale, color: CGColor(gray: 0, alpha: 0.45))
var x = padding
for (panels, columnSize) in zip(columns, columnSizes) {
    // Columns are centered on the tallest one; panels within a column run top to bottom.
    var top = size.height - padding - (contentHeight - columnSize.height) / 2
    for panel in panels {
        let panelSize = CGSize(width: panel.width, height: panel.height)
        let origin = CGPoint(x: (x + (columnSize.width - panelSize.width) / 2).rounded(), y: (top - panelSize.height).rounded())
        context.draw(panel, in: CGRect(origin: origin, size: panelSize))
        top -= panelSize.height + rowGap
    }
    x += columnSize.width + columnGap
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("cannot write \(output)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }
print("\(output) \(Int(size.width))x\(Int(size.height))")
