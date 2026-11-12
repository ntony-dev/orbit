import CoreGraphics
import SwiftUI

// Where a glyph's visible ink sits in its layout box. SF Symbols carry side bearings that differ by symbol, size
// and weight, and their ink is not always centred (backward.fill leans 1.1 pt left of its box at 21 pt), so a
// control whose glyph must meet a margin can trust neither its frame nor a constant per symbol. The ink is
// measured from SwiftUI's own rendering of the glyph, once per glyph, and cached: the player re-evaluates its
// views on every progress tick.
struct GlyphInk: Hashable {
    // Distances from the centre of the glyph's layout box to the left and right edges of its ink.
    var leading: CGFloat
    var trailing: CGFloat

    var width: CGFloat { leading + trailing }

    // How far a frame `diameter` wide, centred on the glyph, reaches past the ink on that side.
    func overhang(_ edge: HorizontalEdge, in diameter: CGFloat) -> CGFloat {
        diameter / 2 - (edge == .leading ? leading : trailing)
    }

    @MainActor
    static func symbol(_ name: String, size: CGFloat, weight: Font.Weight = .semibold) -> GlyphInk {
        let key = SymbolKey(name: name, size: size, weight: weight)
        if let cached = symbolCache[key] { return cached }
        // Large enough for any symbol at this size, so the ink is never cut off by the canvas.
        let canvas = (size * 3).rounded(.up)
        let image = Image(systemName: name).font(.system(size: size, weight: weight))
        let ink = InkMeter.span(of: image, canvas: canvas, alignment: .center).map {
            GlyphInk(leading: canvas / 2 - $0.lowerBound, trailing: $0.upperBound - canvas / 2)
        } ?? GlyphInk(leading: 0, trailing: 0)
        symbolCache[key] = ink
        return ink
    }

    private struct SymbolKey: Hashable {
        let name: String
        let size: CGFloat
        let weight: Font.Weight
    }

    @MainActor private static var symbolCache: [SymbolKey: GlyphInk] = [:]
}

// The room between a piece of text's layout edges and its ink, so text can meet a margin by its ink too. Callers
// measure the character at the edge, or a reference one when that character changes too often to follow.
struct TextBearings: Hashable {
    var leading: CGFloat
    var trailing: CGFloat

    @MainActor
    static func of(_ reference: String, font: Font) -> TextBearings {
        let key = TextKey(reference: reference, font: font)
        if let cached = cache[key] { return cached }
        let text = Text(reference).font(font).fixedSize()
        let canvas: CGFloat = 64
        let leading = InkMeter.span(of: text, canvas: canvas, alignment: .leading)?.lowerBound ?? 0
        let trailing = InkMeter.span(of: text, canvas: canvas, alignment: .trailing).map { canvas - $0.upperBound } ?? 0
        let bearings = TextBearings(leading: leading, trailing: trailing)
        cache[key] = bearings
        return bearings
    }

    private struct TextKey: Hashable {
        let reference: String
        let font: Font
    }

    @MainActor private static var cache: [TextKey: TextBearings] = [:]
}

@MainActor
private enum InkMeter {
    // Eight pixels a point resolves an edge to an eighth of a point, finer than either display scale draws it.
    static let scale: CGFloat = 8

    // The horizontal extent, in points from the canvas's left edge, of every pixel at least half covered: the
    // edge a viewer sees, where antialiasing crosses the midpoint between background and glyph.
    static func span(of content: some View, canvas: CGFloat, alignment: Alignment) -> ClosedRange<CGFloat>? {
        let renderer = ImageRenderer(content: content
            .foregroundStyle(.black)
            .symbolRenderingMode(.monochrome)
            .frame(width: canvas, height: canvas, alignment: alignment))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width
        var maxX = -1
        for row in 0..<height {
            let start = row * width
            for column in 0..<width where alpha[start + column] >= 128 {
                minX = min(minX, column)
                maxX = max(maxX, column)
            }
        }
        guard maxX >= minX else { return nil }
        return CGFloat(minX) / scale...CGFloat(maxX + 1) / scale
    }
}

extension View {
    // Lets a glyph's ink, rather than the frame centred on it, meet the layout edge: the frame and its hover
    // circle reach past the edge by the room between them, into the padding.
    func inkAligned(_ edge: HorizontalEdge, _ ink: GlyphInk, in diameter: CGFloat) -> some View {
        padding(edge == .leading ? .leading : .trailing, -ink.overhang(edge, in: diameter))
    }
}
