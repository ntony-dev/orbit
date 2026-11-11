import OrbitCore
import SwiftUI

// Preferences and accessibility settings resolved once at the root, so leaf views read one value instead of
// combining Preferences with three environment flags each time.
struct OrbitTheme {
    var accent: Color
    var glassPreset: GlassPreset
    var backgroundOpacity: Double
    var showsArtwork: Bool
    var reducesMotion: Bool
    var reducesTransparency: Bool
    var contrast: ColorSchemeContrast
    // Muted average color of the current artwork; only the Tinted preset uses it.
    var artworkTint: Color?
    // Below 1 only for the debug slow-motion argument, so morph frames can be captured mid-flight.
    var animationSpeed: Double = 1

    static let standard = OrbitTheme(
        accent: OrbitPalette.accent(.neutral),
        glassPreset: .clear,
        backgroundOpacity: 0.5,
        showsArtwork: true,
        reducesMotion: false,
        reducesTransparency: false,
        contrast: .standard,
        artworkTint: nil
    )

    var isHighContrast: Bool { contrast == .increased }

    func animation(_ animation: Animation) -> Animation {
        (reducesMotion ? OrbitTokens.Motion.reduced : animation).speed(animationSpeed)
    }

    // Native glass has only the regular and clear variants. Presets choose one, and Tinted adds a native tint;
    // the strength of the blur itself is never changed.
    var glass: Glass {
        switch glassPreset {
        case .clear: .clear
        case .balanced: .regular
        case .tinted: .regular.tint((artworkTint ?? OrbitPalette.backing).opacity(0.62))
        }
    }

    // Opacity of Orbit's own backing layer under the glass. The user's setting scales it within a ceiling per
    // preset, so even 100% never hides the glass completely; accessibility settings raise the floor for legibility.
    var backingOpacity: Double {
        if reducesTransparency { return 0.94 }
        let ceiling: Double = switch glassPreset {
        case .clear: 0.62
        case .balanced: 0.58
        case .tinted: 0.34
        }
        let value = min(1, max(0, backgroundOpacity)) * ceiling
        return isHighContrast ? max(value, 0.6) : value
    }
}

extension EnvironmentValues {
    @Entry var orbitTheme = OrbitTheme.standard
}
