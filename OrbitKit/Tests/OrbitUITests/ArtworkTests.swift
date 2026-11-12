import CoreGraphics
import Foundation
import ImageIO
@testable import OrbitUI
import Testing
import UniformTypeIdentifiers

// A cover on disk that no other test has decoded, so every test starts with a cold memory cache.
private func temporaryCover(side: Int = 640) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "OrbitArtworkTest-\(UUID().uuidString).png")
    let context = try #require(CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

struct ArtworkImagesTests {
    // The menu bar's 32 pt item gets a cover decoded at its own pixel size, not the full download.
    @Test func menuBarArtworkIsDecodedAtTheItemsSize() async throws {
        let url = try temporaryCover()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ArtworkImages.cached(url, points: 32, scale: 2) == nil)
        let image = try #require(await ArtworkImages.load(url, points: 32, scale: 2))
        #expect(image.width == 64)
        #expect(ArtworkImages.cached(url, points: 32, scale: 2) === image)
        #expect(ArtworkImages.cached(url, points: 32, scale: 1) == nil)
        #expect(await ArtworkImages.load(url, points: 32, scale: 1)?.width == 32)
    }
}
