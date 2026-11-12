import OrbitCore
import SwiftUI

// Every size, radius, font and timing in OrbitUI comes from here; colors live in OrbitPalette.
enum OrbitTokens {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        // Ink to ink between the play disc and the previous and next glyphs, Apple Music's mini player's proportion.
        static let transportGroup: CGFloat = 34
        // The volume row's visible gaps: the bar's end to the queue glyph, and the queue glyph to the device slot.
        static let volumeToQueue: CGFloat = 10
        static let queueToDevice: CGFloat = 12
    }

    enum Radius {
        // Large enough that a pill-height surface clamps to a capsule, so the pill and the expanded card share one
        // shape and the morph only animates the frame.
        static let surface: CGFloat = 26
        static let artworkLarge: CGFloat = 12
        static let artwork: CGFloat = 7
        static let artworkSmall: CGFloat = 5
        static let row: CGFloat = 10
        static let control: CGFloat = 9
        static let field: CGFloat = 10
        static let segment: CGFloat = 9
        static let callout: CGFloat = 14
    }

    enum Size {
        // Room around the surface so the glass shadow is not clipped by the canvas edge.
        static let canvasMargin: CGFloat = 20
        static let expandedWidth: CGFloat = 344

        static let pillArtworkCompact: CGFloat = 26
        static let pillArtworkRegular: CGFloat = 34
        static let nowPlayingArtwork: CGFloat = 76
        static let stripArtwork: CGFloat = 30
        static let rowArtwork: CGFloat = 34
        static let detailArtwork: CGFloat = 64

        static let iconButton: CGFloat = 28
        static let transportButton: CGFloat = 36
        static let skipTransportButton: CGFloat = 40
        static let primaryTransportButton: CGFloat = 54
        // The row of elapsed and remaining time under the seek bar: one line of the timecode font.
        static let timecodeRow: CGFloat = 13
        // Fixed slots in the volume row, so neither the bar nor the queue button moves when the speaker glyph
        // changes with the level or the device glyph with the device: the speaker sits at the slot's leading edge,
        // the device at its trailing edge.
        static let speakerSlot: CGFloat = 20
        static let deviceSlot: CGFloat = 22
        static let rowHeight: CGFloat = 46
        static let trackRowHeight: CGFloat = 40
        // Song rows that lead with artwork: search results and the queue.
        static let artworkTrackRowHeight: CGFloat = 42
        static let segmentHeight: CGFloat = 30
        static let fieldHeight: CGFloat = 30
        static let sliderTrack: CGFloat = 4
        static let sliderTrackActive: CGFloat = 6
        static let sliderHitHeight: CGFloat = 18
        static let sliderKnob: CGFloat = 12
        static let capsuleButton: CGFloat = 26
        static let pillControlCompact: CGFloat = 26
        static let pillControlRegular: CGFloat = 30
        static let playingIndicator: CGFloat = 20
        // Width over which a title too long for its space fades out instead of ending in an ellipsis.
        static let truncationFade: CGFloat = 30

        // Bounds for screens that size to their content: short enough that five liked songs leave no hole, tall
        // enough that a long library still shows ten rows.
        static let fittedMinHeight: CGFloat = 248
        static let fittedMaxHeight: CGFloat = 548
        // What a gated screen (signed out, not allowlisted) needs for its message and one action.
        static let gatedHeight: CGFloat = 330
        // Room an empty, loading or error state keeps inside a fitted list, so the message never looks cramped.
        static let listStateHeight: CGFloat = 196
        static let listEdgeFade: CGFloat = 20
        // The drawers the player reveals under its volume row show this many rows before they scroll.
        static let deviceListVisibleRows = 4
        static let queueVisibleRows = 5
        // The player does not fit to content: its controls fill this, and a drawer or notice adds to it.
        static let playerHeight: CGFloat = 319

        static func pill(_ size: PillSize) -> CGSize {
            switch size {
            case .compact: CGSize(width: 212, height: 40)
            case .regular: CGSize(width: 272, height: 52)
            }
        }

        static func canvas(for surface: CGSize) -> CGSize {
            CGSize(width: surface.width + canvasMargin * 2, height: surface.height + canvasMargin * 2)
        }
    }

    enum Icon {
        static let small: CGFloat = 11
        static let regular: CGFloat = 13
        static let transport: CGFloat = 16
        // Previous and next: drawn about 29.75 wide, a third wider than at the transport size, to read as a pair
        // with the larger play disc.
        static let skipTransport: CGFloat = 21
        static let primaryTransport: CGFloat = 22
        static let indicator: CGFloat = 14
        // Every glyph in the panel's top bar (back, settings, collapse), so the chrome reads as one set.
        static let chrome: CGFloat = 12
    }

    enum Typography {
        static let title = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let rowTitle = Font.system(size: 13, weight: .medium)
        static let subheadline = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let captionEmphasized = Font.system(size: 11, weight: .semibold)
        static let sectionHeading = Font.system(size: 11, weight: .semibold)
        static let timecode = Font.system(size: 10.5, weight: .medium).monospacedDigit()
        static let timecodeEmphasized = Font.system(size: 10.5, weight: .semibold).monospacedDigit()
        static let pillTitleCompact = Font.system(size: 12, weight: .semibold)
        static let pillTitleRegular = Font.system(size: 13, weight: .semibold)
        static let pillSubtitle = Font.system(size: 11)
        static let segment = Font.system(size: 12, weight: .medium)
        // The player's title and artist: two steps apart in size and weight, so the pair reads as one block with
        // a clear lead whether the title takes one line or two.
        static let nowPlayingTitle = Font.system(size: 16, weight: .semibold)
        static let nowPlayingArtist = Font.system(size: 13)
    }

    // Control feedback is effectively instant, navigation brisk, and the morph just long enough to read as the
    // pill growing rather than a window being swapped.
    enum Motion {
        static let morph = Animation.spring(duration: 0.32, bounce: 0.12)
        static let navigate = Animation.smooth(duration: 0.22)
        static let content = Animation.smooth(duration: 0.24)
        static let hover = Animation.easeOut(duration: 0.07)
        static let press = Animation.easeOut(duration: 0.04)
        static let reduced = Animation.easeInOut(duration: 0.12)
        // The pill fades out before the surface has grown much, and the expanded content fades in once there is
        // room for it, so neither ever floats inside a surface of the wrong size.
        static let pillFadeOut = Animation.easeOut(duration: 0.07)
        static let surfaceFadeIn = Animation.easeOut(duration: 0.18).delay(0.05)
        static let screenFadeOut = Animation.easeOut(duration: 0.1)
        // When a morph has visibly finished, so the canvas can shrink without clipping the spring's tail.
        static let settle: Duration = .milliseconds(420)
        // Long enough to read "Now playing" on a switched row before the panel collapses on its own.
        static let confirmationHold: Duration = .milliseconds(700)
        static let searchDebounce: Duration = .milliseconds(320)
        static let volumeThrottle: Duration = .milliseconds(120)
        static let progressInterval: TimeInterval = 0.5
        static let navigationOffset: CGFloat = 14
        // Collapsing is a return to rest: a firmer spring with no visible overshoot, the card's content gone
        // almost at once and the pill arriving while the surface is still closing in, so there is no empty beat.
        static let collapse = Animation.spring(duration: 0.26, bounce: 0.04)
        static let collapseContentFadeOut = Animation.easeOut(duration: 0.07)
        static let collapsePillFadeIn = Animation.easeOut(duration: 0.14).delay(0.03)
        static let selection = Animation.easeOut(duration: 0.07)
        static let loadingPulse = Animation.easeInOut(duration: 0.9)
        // Shuffle, repeat, like and play/pause answer a click at once; only the color settles.
        static let toggle = Animation.easeOut(duration: 0.08)
    }
}
