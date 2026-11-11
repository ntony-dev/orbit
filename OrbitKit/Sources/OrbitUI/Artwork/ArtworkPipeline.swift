import CoreGraphics
import Foundation
import ImageIO

struct ArtworkKey: Hashable, Sendable {
    let url: URL
    let pixelSize: Int
}

struct DecodedArtwork: Sendable {
    let image: CGImage
    // Average of the downsampled image in sRGB, used to tint the Tinted glass preset.
    let averageColor: SIMD3<Double>?
}

// Fetches, downsamples and decodes artwork off the main actor. Each image is decoded once at the pixel size it is
// shown at, concurrent requests for the same key share one task, and HTTP responses are also kept on disk by the
// session's URLCache, so scrolling and track changes never decode on the main thread.
actor ArtworkPipeline {
    static let shared = ArtworkPipeline()

    nonisolated let memory = ArtworkMemoryCache()
    private var inFlight: [ArtworkKey: Task<DecodedArtwork?, Never>] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    func artwork(for key: ArtworkKey) async -> DecodedArtwork? {
        if let cached = memory[key] { return cached }
        if let running = inFlight[key] { return await running.value }
        let session = session
        let task = Task.detached(priority: .utility) { await Self.load(key, session: session) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { memory[key] = result }
        return result
    }

    private static func load(_ key: ArtworkKey, session: URLSession) async -> DecodedArtwork? {
        let data: Data
        do {
            if key.url.isFileURL {
                data = try Data(contentsOf: key.url, options: .mappedIfSafe)
            } else {
                data = try await session.data(from: key.url).0
            }
        } catch {
            return nil
        }
        guard !Task.isCancelled, let image = downsample(data, to: key.pixelSize) else { return nil }
        return DecodedArtwork(image: image, averageColor: averageColor(of: image))
    }

    private static func downsample(_ data: Data, to pixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(16, pixelSize),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private static func averageColor(of image: CGImage) -> SIMD3<Double>? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2])) / 255
    }
}

// NSCache is documented as thread-safe, which is what makes sharing it across isolation domains sound.
final class ArtworkMemoryCache: @unchecked Sendable {
    private let cache: NSCache<Entry.Key, Entry> = {
        let cache = NSCache<Entry.Key, Entry>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    subscript(key: ArtworkKey) -> DecodedArtwork? {
        get { cache.object(forKey: Entry.Key(key))?.artwork }
        set {
            guard let newValue else {
                cache.removeObject(forKey: Entry.Key(key))
                return
            }
            let cost = newValue.image.bytesPerRow * newValue.image.height
            cache.setObject(Entry(newValue), forKey: Entry.Key(key), cost: cost)
        }
    }

    final class Entry {
        let artwork: DecodedArtwork

        init(_ artwork: DecodedArtwork) {
            self.artwork = artwork
        }

        final class Key: NSObject {
            let key: ArtworkKey

            init(_ key: ArtworkKey) {
                self.key = key
            }

            override var hash: Int { key.hashValue }

            override func isEqual(_ object: Any?) -> Bool {
                (object as? Key)?.key == key
            }
        }
    }
}
