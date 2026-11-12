import AppKit
import OrbitCore
import SwiftUI

// Semantic colors. Text uses the hierarchical styles (.primary, .secondary, .tertiary) so it picks up glass
// vibrancy; everything here is either adaptive or derived from the primary label color.
public enum OrbitPalette {
    // Each preset has a lighter dark-mode variant and a deeper light-mode variant, because the same pastel that
    // reads well on dark glass disappears on light glass. Neutral is the label color itself, nearly white in dark.
    public static func accent(_ choice: AccentChoice) -> Color {
        switch choice {
        case .neutral: adaptive(light: 0x2B2F36, dark: 0xE6EAEE)
        case .mint: adaptive(light: 0x23936C, dark: 0x80D5B1)
        case .ice: adaptive(light: 0x2F6FD0, dark: 0x91B7F0)
        case .amber: adaptive(light: 0xA86F1C, dark: 0xE3BD83)
        case .lavender: adaptive(light: 0x7058C9, dark: 0xB6A0EF)
        case .custom(let rgb): custom(rgb)
        }
    }

    public static func accentName(_ choice: AccentChoice) -> String {
        switch choice {
        case .neutral: "Neutral"
        case .mint: "Soft Mint"
        case .ice: "Ice Blue"
        case .amber: "Warm Amber"
        case .lavender: "Muted Lavender"
        case .custom: "Custom"
        }
    }

    // The one solid fill in the UI (play disc, primary capsule): label-colored, with the glyph knocked out.
    static let prominentFill = adaptive(light: 0x1D1E20, dark: 0xF4F5F7)
    static let prominentGlyph = adaptive(light: 0xFFFFFF, dark: 0x111214)

    static let warning = adaptive(light: 0xB25D00, dark: 0xF2B26B)

    // The fill Orbit draws beneath the native glass: the user's background opacity over a legibility floor.
    static let backing = adaptive(light: 0xF7F8FA, dark: 0x16181C)

    // Dark glyphs on light glass lose more to the same opacity than light glyphs on dark glass, so light
    // appearance keeps disabled controls a step stronger; increased contrast raises both.
    static func disabledOpacity(_ scheme: ColorScheme, contrast: ColorSchemeContrast) -> Double {
        let base = scheme == .dark ? 0.34 : 0.42
        return contrast == .increased ? base + 0.14 : base
    }

    // A disabled row still carries the reason it is unavailable, so it dims less than a lone glyph.
    static func disabledRowOpacity(contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? 0.62 : 0.48
    }

    static func hoverFill(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.14 : 0.075)
    }

    static func pressedFill(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.22 : 0.13)
    }

    static func quietFill(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.12 : 0.055)
    }

    // The navigation's glass highlight takes only a breath of the accent: enough to carry a colored accent, not
    // enough to stop the glass from reading as glass.
    static func selectionTint(accent: Color) -> Color {
        accent.opacity(0.12)
    }

    // The same highlight without glass, for Reduce Transparency.
    static func selectionFill(accent: Color, contrast: ColorSchemeContrast) -> Color {
        accent.opacity(contrast == .increased ? 0.32 : 0.2)
    }

    static func selectionStroke(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.45 : 0.1)
    }

    static func sliderTrack(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.34 : 0.16)
    }

    static func separator(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.3 : 0.09)
    }

    static func surfaceStroke(contrast: ColorSchemeContrast) -> Color {
        .primary.opacity(contrast == .increased ? 0.38 : 0)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    // A custom color is kept as chosen, but nudged toward the label color on the side where it would vanish:
    // very light picks darken on light glass, very dark picks lighten on dark glass.
    private static func custom(_ rgb: OrbitCore.RGBColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let base = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            let luminance = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
            if !isDark, luminance > 0.62 {
                return base.blended(withFraction: 0.45, of: .black) ?? base
            }
            if isDark, luminance < 0.22 {
                return base.blended(withFraction: 0.45, of: .white) ?? base
            }
            return base
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
