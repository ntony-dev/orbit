import SwiftUI

// The single floating object. The pill and every expanded screen render inside one of these, so a morph is only
// this surface changing size while its content cross-fades; the glass never splits or swaps.
struct GlassSurface<Content: View>: View {
    let size: CGSize
    var interactive = false
    @ViewBuilder let content: Content

    @Environment(\.orbitTheme) private var theme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: OrbitTokens.Radius.surface, style: .continuous)
    }

    var body: some View {
        ZStack {
            // Drawn beneath the glass, so the glass refracts it like any other backdrop rather than being veiled.
            shape.fill(OrbitPalette.backing.opacity(theme.backingOpacity))
            content
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .glassEffect(interactive ? theme.glass.interactive() : theme.glass, in: shape)
            if theme.isHighContrast {
                shape.strokeBorder(OrbitPalette.surfaceStroke(contrast: theme.contrast), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
