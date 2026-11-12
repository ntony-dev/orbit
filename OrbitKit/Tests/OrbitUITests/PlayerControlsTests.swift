import CoreGraphics
import OrbitCore
@testable import OrbitUI
import SwiftUI
import Testing

// Spotify's play/pause, measured from its desktop app: a 32 pt disc around a 16 pt icon whose pause bars are
// 12 x 14 and whose rounded play triangle is about 12.3 x 14 with its bounds 1.15 right of centre.
struct PlaybackGlyphTests {
    private let diameter = OrbitTokens.Size.primaryTransportButton
    private var geometry: PlaybackGlyphGeometry { PlaybackGlyphGeometry(box: diameter * PlaybackGlyphGeometry.discToBox) }
    private var centre: CGFloat { geometry.box / 2 }

    private func bounds(_ path: Path) -> CGRect {
        path.cgPath.boundingBoxOfPath
    }

    @Test func pauseMatchesSpotifysProportionsAndIsCentred() {
        let pause = bounds(geometry.pausePath())
        #expect(abs(pause.height / diameter - 14.0 / 32) < 0.001)
        #expect(abs(pause.width / diameter - 12.0 / 32) < 0.001)
        #expect(abs(pause.midX - centre) < 0.001)
        #expect(abs(pause.midY - centre) < 0.001)
    }

    @Test func playIsOpticallyCentredLikeSpotifys() {
        let play = bounds(geometry.playPath())
        let unit = geometry.box / 16
        #expect(abs(play.height / diameter - 14.0 / 32) < 0.002)
        #expect(abs(play.width / diameter - 12.29 / 32) < 0.002)
        #expect(abs(play.midY - centre) < 0.001)
        // Right of centre by its bounds, left of centre by its mass: between the two naive alignments.
        #expect(abs((play.midX - centre) / unit - 1.15) < 0.02)
        let vertices = geometry.playVertices
        let centroid = vertices.map(\.x).reduce(0, +) / 3
        #expect(centroid < centre && play.midX > centre)
    }

    @Test func togglingKeepsTheGlyphInPlace() {
        let pause = bounds(geometry.pausePath())
        let play = bounds(geometry.playPath())
        #expect(abs(pause.height - play.height) < 0.05)
        #expect(abs(pause.midY - play.midY) < 0.001)
        #expect(pause.minX >= 0 && play.maxX <= geometry.box)
    }
}
