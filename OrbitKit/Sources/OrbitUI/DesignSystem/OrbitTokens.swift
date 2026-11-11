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
        static let primaryTransportButton: CGFloat = 46
        static let rowHeight: CGFloat = 46
        static let trackRowHeight: CGFloat = 40
        static let segmentHeight: CGFloat = 30
        static let fieldHeight: CGFloat = 30
        static let sliderTrack: CGFloat = 4
        static let sliderTrackActive: CGFloat = 6
        static let sliderHitHeight: CGFloat = 18
        static let sliderKnob: CGFloat = 12

        static func pill(_ size: PillSize) -> CGSize {
            switch size {
            case .compact: CGSize(width: 212, height: 40)
            case .regular: CGSize(width: 272, height: 52)
            }
        }

        static func pillArtwork(_ size: PillSize) -> CGFloat {
            size == .compact ? pillArtworkCompact : pillArtworkRegular
        }

        static func canvas(for surface: CGSize) -> CGSize {
            CGSize(width: surface.width + canvasMargin * 2, height: surface.height + canvasMargin * 2)
        }
    }

    enum Icon {
        static let small: CGFloat = 11
        static let regular: CGFloat = 13
        static let transport: CGFloat = 16
        static let primaryTransport: CGFloat = 22
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
        static let pillTitleCompact = Font.system(size: 12, weight: .semibold)
        static let pillTitleRegular = Font.system(size: 13, weight: .semibold)
        static let pillSubtitle = Font.system(size: 11)
        static let segment = Font.system(size: 12, weight: .medium)
    }

    enum Motion {
        static let morph = Animation.spring(duration: 0.44, bounce: 0.16)
        static let navigate = Animation.smooth(duration: 0.32)
        static let content = Animation.smooth(duration: 0.36)
        static let hover = Animation.easeOut(duration: 0.14)
        static let press = Animation.easeOut(duration: 0.08)
        static let reduced = Animation.easeInOut(duration: 0.16)
        // Long enough to read "Now playing" on a switched row before the panel collapses on its own.
        static let confirmationHold: Duration = .milliseconds(700)
        static let searchDebounce: Duration = .milliseconds(320)
        static let volumeThrottle: Duration = .milliseconds(120)
        static let progressInterval: TimeInterval = 0.5
        static let navigationOffset: CGFloat = 18
    }
}

extension Alignment {
    init(_ anchor: PanelAnchor) {
        switch (anchor.vertical, anchor.horizontal) {
        case (.top, .leading): self = .topLeading
        case (.top, .center): self = .top
        case (.top, .trailing): self = .topTrailing
        case (.bottom, .leading): self = .bottomLeading
        case (.bottom, .center): self = .bottom
        case (.bottom, .trailing): self = .bottomTrailing
        }
    }
}

extension UnitPoint {
    init(_ anchor: PanelAnchor) {
        let x: CGFloat = switch anchor.horizontal {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        self.init(x: x, y: anchor.vertical == .top ? 0 : 1)
    }
}
