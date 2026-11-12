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
        glassPreset: .balanced,
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

    // Native glass keeps the tone of whatever is behind it, so white text over a bright page or dark text over a
    // terminal can fall below 3:1. Apple pairs clear glass with a dimming layer for exactly this; Orbit's backing
    // never drops below this floor, so 0% still shows the desktop's shapes and colors but never at the cost of the
    // text. Regular glass already pulls toward a mid tone and needs less.
    func legibilityFloor(for scheme: ColorScheme) -> Double {
        switch (glassPreset, scheme) {
        case (.clear, .dark): 0.56
        case (.clear, _): 0.46
        case (_, .dark): 0.45
        case (_, _): 0.3
        }
    }

    // Opacity of Orbit's own fill under the glass, the only thing the background opacity setting changes. It runs
    // in a straight line from the preset's legibility floor to one shared ceiling, so the setting spans a wide,
    // even range in every preset instead of being squeezed into what the floor leaves over. The ceiling stops
    // short of opaque so the glass still reads as glass; Reduce Transparency goes past it.
    func surfaceFill(for scheme: ColorScheme) -> Double {
        if reducesTransparency { return 0.94 }
        let floor = legibilityFloor(for: scheme)
        let value = floor + min(1, max(0, backgroundOpacity)) * (Self.maximumFill - floor)
        return isHighContrast ? max(value, 0.8) : value
    }

    static let maximumFill = 0.88
}

extension EnvironmentValues {
    @Entry var orbitTheme = OrbitTheme.standard
}
