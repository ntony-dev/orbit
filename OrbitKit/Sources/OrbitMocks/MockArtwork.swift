import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Fixture artwork is rendered to local PNG files so `--demo` and previews need no network.
public enum MockArtwork {
    struct Palette: Hashable, Sendable {
        var start: UInt32
        var end: UInt32

        init(_ start: UInt32, _ end: UInt32) {
            self.start = start
            self.end = end
        }
    }

    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitMockArtwork", isDirectory: true)
    static let pixelSize = 300

    public static func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).png")
    }

    static func render(_ artwork: [String: Palette]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (key, palette) in artwork {
            let url = url(for: key)
            guard !FileManager.default.fileExists(atPath: url.path), let image = image(for: palette, seed: key) else { continue }
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func image(for palette: Palette, seed: String) -> CGImage? {
        let size = CGFloat(pixelSize)
        guard let context = CGContext(
            data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let colors = [palette.start, palette.end].map { hex in
            CGColor(
                srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: 1
            )
        }
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])

        // A stable per-key highlight keeps covers that share a palette distinguishable.
        let hash = seed.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        let center = CGPoint(x: size * (0.25 + Double(hash % 50) / 100), y: size * (0.25 + Double((hash / 50) % 50) / 100))
        let glow = CGGradient(
            colorsSpace: nil,
            colors: [CGColor(gray: 1, alpha: 0.38), CGColor(gray: 1, alpha: 0)] as CFArray,
            locations: [0, 1]
        )!
        context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: size * 0.42, options: [])
        return context.makeImage()
    }
}
