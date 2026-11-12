import AppKit
import CoreGraphics
@testable import OrbitUI
import SwiftUI
import Testing

// The Now Playing view's geometry, in the expanded surface's points: x 0 to 344, content margins at 16 and 328,
// the play disc centred on 172.
@MainActor
struct NowPlayingLayoutTests {
    private let margin = OrbitTokens.Spacing.xl
    private let width = OrbitTokens.Size.expandedWidth
    private var centre: CGFloat { width / 2 }
    private var trailingMargin: CGFloat { width - margin }

    @Test func thePlayerIsExactlyTheStackOfItsRows() {
        let spacing = OrbitTokens.Spacing.self
        let size = OrbitTokens.Size.self
        let topBar = spacing.l + spacing.xxs + size.stripArtwork + spacing.xs
        let track = spacing.s + size.nowPlayingArtwork
        let progress = spacing.m + spacing.xxs + size.sliderHitHeight + size.timecodeRow
        let transport = spacing.xs + size.primaryTransportButton
        let volume = spacing.m + size.iconButton
        let slackAboveTabs = spacing.s
        let tabs = spacing.s + size.segmentHeight + spacing.l
        #expect(topBar + track + progress + transport + volume + slackAboveTabs + tabs == size.playerHeight)
        #expect(size.playerHeight == 319)
    }

    @Test func theSurfaceAndCanvasFollowThePlayerHeight() {
        let surface = PanelNavigator().screenSize
        #expect(surface == CGSize(width: 344, height: 319))
        #expect(PanelMetrics.canvas(for: surface) == CGSize(width: 384, height: 359))
    }

    @Test func theTimeRowHoldsALineOfTheTimecodeFont() {
        for weight in [NSFont.Weight.medium, .semibold] {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: weight)
            #expect(font.ascender - font.descender + font.leading <= OrbitTokens.Size.timecodeRow)
        }
    }

    @Test func previousAndNextSitAnInkGapFromTheDiscWhateverTheirBearings() {
        let disc = OrbitTokens.Size.primaryTransportButton
        let leaning = GlyphInk(leading: 16, trailing: 13.75)
        let mirrored = GlyphInk(leading: 13.75, trailing: 16)
        #expect(centre - disc / 2 == 145 && centre + disc / 2 == 199)
        #expect(centre + TransportLayout.previousOffset(disc: disc, ink: leaning) + leaning.trailing == 111)
        #expect(centre + TransportLayout.nextOffset(disc: disc, ink: mirrored) - mirrored.leading == 233)
        // A symmetric glyph lands the same: only the ink facing the disc matters.
        let even = GlyphInk(leading: 10, trailing: 10)
        #expect(centre + TransportLayout.previousOffset(disc: disc, ink: even) + even.trailing == 111)
        #expect(centre + TransportLayout.nextOffset(disc: disc, ink: even) - even.leading == 233)
    }

    @Test func anInkAlignedFrameReachesPastTheMarginByItsGlyphsBearing() {
        let ink = GlyphInk(leading: 9.5, trailing: 8.75)
        #expect(ink.overhang(.leading, in: 36) == 8.5)
        #expect(ink.overhang(.trailing, in: 36) == 9.25)
        // A frame pulled out by its overhang puts the ink on the margin: the frame's centre is the glyph's.
        let frameLeading = margin - ink.overhang(.leading, in: 36)
        #expect(frameLeading + 18 - ink.leading == margin)
    }

    @Test func theRealTransportRowMeetsTheSpecification() {
        let shuffle = GlyphInk.symbol("shuffle", size: OrbitTokens.Icon.transport)
        let previous = GlyphInk.symbol("backward.fill", size: OrbitTokens.Icon.skipTransport)
        let next = GlyphInk.symbol("forward.fill", size: OrbitTokens.Icon.skipTransport)
        let disc = OrbitTokens.Size.primaryTransportButton
        #expect((29...30).contains(previous.width))
        #expect((29...30).contains(next.width))
        // backward.fill's ink leans left of its box and forward.fill's right, which is why each is placed by the
        // ink that faces the disc rather than by its frame.
        #expect(previous.leading > previous.trailing && next.trailing > next.leading)
        let previousLeft = centre + TransportLayout.previousOffset(disc: disc, ink: previous) - previous.leading
        let nextRight = centre + TransportLayout.nextOffset(disc: disc, ink: next) + next.trailing
        for repeatSymbol in ["repeat", "repeat.1"] {
            let repeatInk = GlyphInk.symbol(repeatSymbol, size: OrbitTokens.Icon.transport)
            let outerLeft = previousLeft - (margin + shuffle.width)
            let outerRight = (trailingMargin - repeatInk.width) - nextRight
            #expect((45...49).contains(outerLeft), "shuffle to previous: \(outerLeft)")
            #expect((45...49).contains(outerRight), "next to \(repeatSymbol): \(outerRight)")
        }
        // The skip buttons' 40 pt click areas hold their glyphs and stay clear of the disc and the outer buttons.
        let skip = OrbitTokens.Size.skipTransportButton
        #expect(previous.leading <= skip / 2 && previous.trailing <= skip / 2)
        let previousFrameRight = centre + TransportLayout.previousOffset(disc: disc, ink: previous) + skip / 2
        #expect(previousFrameRight < centre - disc / 2)
        let shuffleFrameRight = margin - shuffle.overhang(.leading, in: OrbitTokens.Size.transportButton) + OrbitTokens.Size.transportButton
        #expect(shuffleFrameRight < centre + TransportLayout.previousOffset(disc: disc, ink: previous) - skip / 2)
    }

    @Test func everyDeviceAndSpeakerGlyphFitsItsSlot() {
        let drawerGlyph = OrbitTokens.Icon.regular + 1
        let devices = ["laptopcomputer", "iphone", "ipad", "hifispeaker", "tv", "car", "speaker.wave.2"]
        for symbol in devices {
            let ink = GlyphInk.symbol(symbol, size: drawerGlyph)
            #expect(ink.width > 0 && ink.width <= OrbitTokens.Size.deviceSlot, "\(symbol) is \(ink.width) wide")
            #expect(max(ink.leading, ink.trailing) <= OrbitTokens.Size.iconButton / 2, "\(symbol) overflows its circle")
        }
        let speakers = ["speaker.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill", "speaker.slash.fill"]
        for symbol in speakers {
            let ink = GlyphInk.symbol(symbol, size: OrbitTokens.Icon.regular)
            #expect(ink.width > 0 && ink.width <= OrbitTokens.Size.speakerSlot, "\(symbol) is \(ink.width) wide")
        }
    }

    @Test func theVolumeBarKeepsItsExtent() {
        let barStart = margin + OrbitTokens.Size.speakerSlot + OrbitTokens.Spacing.xs
        let queue = GlyphInk.symbol("list.bullet", size: OrbitTokens.Icon.regular + 1)
        let barEnd = trailingMargin - OrbitTokens.Size.deviceSlot - OrbitTokens.Spacing.queueToDevice - queue.width
            - OrbitTokens.Spacing.volumeToQueue
        #expect(barStart == 40)
        #expect(abs(barEnd - 269) <= 1, "the bar ends at \(barEnd)")
    }

    @Test func inkIsMeasuredOnceAndAgreesWithItself() {
        let first = GlyphInk.symbol("heart.fill", size: 15)
        #expect(GlyphInk.symbol("heart.fill", size: 15) == first)
        #expect(abs(first.width - 15) <= 0.5)
        // The outline and filled hearts share their outline, so liking a song never moves the heart.
        #expect(abs(GlyphInk.symbol("heart", size: 15).trailing - first.trailing) <= 0.125)
    }

    @Test func aDigitsBearingsComeFromItsOwnShape() {
        let zero = TextBearings.of("0", font: OrbitTokens.Typography.timecode)
        let one = TextBearings.of("1", font: OrbitTokens.Typography.timecode)
        #expect(zero.leading > 0 && zero.leading < 1.5 && zero.trailing > 0 && zero.trailing < 1.5)
        #expect(one.leading > zero.leading && one.trailing > zero.trailing)
    }
}
