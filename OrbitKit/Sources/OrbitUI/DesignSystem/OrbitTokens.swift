import OrbitCore
import SwiftUI

// First-pass tokens. Every color, size, radius, font and timing in OrbitUI comes from here.
public enum OrbitTokens {
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }

    public enum Radius {
        public static let artwork: CGFloat = 8
        public static let row: CGFloat = 10
        public static let card: CGFloat = 26
    }

    public enum Size {
        // Room around the glass so its shadow is not clipped by the canvas edge.
        public static let canvasMargin: CGFloat = 18
        public static let expandedCard = CGSize(width: 340, height: 430)
        public static let pillArtwork: CGFloat = 26
        public static let nowPlayingArtwork: CGFloat = 54
        public static let playlistArtwork: CGFloat = 32
        public static let controlIcon: CGFloat = 15
        public static let primaryControlIcon: CGFloat = 20

        public static func pill(_ size: PillSize) -> CGSize {
            switch size {
            case .compact: CGSize(width: 210, height: 40)
            case .regular: CGSize(width: 250, height: 48)
            }
        }

        public static func canvas(for surface: CGSize) -> CGSize {
            CGSize(width: surface.width + canvasMargin * 2, height: surface.height + canvasMargin * 2)
        }
    }

    public enum Typography {
        public static let pillTitle = Font.system(size: 13, weight: .semibold)
        public static let trackTitle = Font.system(size: 15, weight: .semibold)
        public static let secondary = Font.system(size: 12, weight: .regular)
        public static let sectionHeading = Font.system(size: 11, weight: .semibold)
        public static let rowTitle = Font.system(size: 13, weight: .medium)
        public static let caption = Font.system(size: 11, weight: .regular).monospacedDigit()
    }

    public enum Motion {
        public static let morph = Animation.spring(response: 0.42, dampingFraction: 0.86)
        public static let reducedMorph = Animation.easeInOut(duration: 0.18)
        public static let press = Animation.easeOut(duration: 0.12)
        public static let dragThreshold = PanelGeometry.dragThreshold
        public static let progressTick: TimeInterval = 0.5

        public static func morph(reduced: Bool) -> Animation {
            reduced ? reducedMorph : morph
        }
    }

    public enum Palette {
        public static let primaryText = Color.primary
        public static let secondaryText = Color.secondary
        public static let separator = Color.primary.opacity(0.12)
        public static let rowHover = Color.primary.opacity(0.08)
        public static let track = Color.primary.opacity(0.16)
        public static let warning = Color(red: 0.95, green: 0.71, blue: 0.42)

        public static func accent(_ choice: AccentChoice) -> Color {
            switch choice {
            case .neutral: Color(hex: 0xCBD1D7)
            case .mint: Color(hex: 0x80D5B1)
            case .ice: Color(hex: 0x91B7F0)
            case .amber: Color(hex: 0xE3BD83)
            case .lavender: Color(hex: 0xB6A0EF)
            case .custom(let rgb): Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
        }
    }

    public enum Material {
        // Native glass offers only regular and clear; presets layer Orbit's own tint on top of those.
        public static func glass(_ preset: GlassPreset, accent: Color) -> Glass {
            switch preset {
            case .clear: .clear
            case .balanced: .regular
            case .tinted: .regular.tint(accent.opacity(0.35))
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
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
