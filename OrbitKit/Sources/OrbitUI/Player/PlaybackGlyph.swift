import AppKit
import SwiftUI

// Play and pause drawn as shapes rather than SF Symbols, whose differing side bearings made the glyph shift when
// toggling and left the triangle visibly off-centre. Both glyphs live in the same square box, measured in
// sixteenths of it, with Spotify's proportions: the box is half the disc's diameter, the pause bars are 4 wide,
// 4 apart and 14 tall, and the play triangle is equilateral with the same visible height. The triangle's left edge
// sits 3 in, which puts its visible bounds about 1.15 right of centre and its area centroid about 0.67 left of
// it: optically centred, between bounding-box centring (which looks left-heavy) and centroid centring (which
// overshoots).
struct PlaybackGlyphGeometry {
    let box: CGFloat

    // Spotify's play/pause disc is twice the size of its icon box.
    static let discToBox: CGFloat = 0.5

    private var unit: CGFloat { box / 16 }
    private var cornerRadius: CGFloat { 0.7 * unit }

    var pauseBars: [CGRect] {
        [2, 10].map { x in CGRect(x: x * unit, y: unit, width: 4 * unit, height: 14 * unit) }
    }

    // The sharp triangle before its corners are rounded: side 15, pointing right, with its tip on the box edge.
    var playVertices: [CGPoint] {
        let side = 15 * unit
        let left = 3 * unit
        return [
            CGPoint(x: left, y: (box - side) / 2),
            CGPoint(x: left + side * 3.squareRoot() / 2, y: box / 2),
            CGPoint(x: left, y: (box + side) / 2),
        ]
    }

    func pausePath() -> Path {
        var path = Path()
        for bar in pauseBars {
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .circular)
        }
        return path
    }

    func playPath() -> Path {
        let corners = playVertices
        var path = Path()
        path.move(to: CGPoint(x: corners[0].x, y: box / 2))
        for index in corners.indices {
            path.addArc(
                tangent1End: corners[index],
                tangent2End: corners[(index + 1) % corners.count],
                radius: cornerRadius
            )
        }
        path.closeSubpath()
        return path
    }
}

// Drawn into template images rather than as SwiftUI shapes: on the pill's glass a shape filled with the
// hierarchical primary style renders at a fraction of a symbol's brightness, while a template image is tinted
// exactly like the SF Symbols beside it.
struct PlaybackGlyph: View {
    let isPlaying: Bool
    let box: CGFloat

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        let geometry = PlaybackGlyphGeometry(box: box)
        ZStack {
            Self.image(geometry.pausePath(), box: box)
                .opacity(isPlaying ? 1 : 0)
            Self.image(geometry.playPath(), box: box)
                .opacity(isPlaying ? 0 : 1)
        }
        .frame(width: box, height: box)
        .animation(theme.animation(OrbitTokens.Motion.toggle), value: isPlaying)
        .accessibilityHidden(true)
    }

    private static func image(_ path: Path, box: CGFloat) -> Image {
        let cgPath = path.cgPath
        let image = NSImage(size: NSSize(width: box, height: box), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return Image(nsImage: image).renderingMode(.template)
    }
}
