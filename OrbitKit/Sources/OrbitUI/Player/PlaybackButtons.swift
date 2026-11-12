import OrbitCore
import OrbitEngine
import SwiftUI

// Play/pause everywhere it appears. Enabled only when the active device allows the transition it would make.
struct PlayPauseButton: View {
    var diameter: CGFloat = OrbitTokens.Size.iconButton
    var glyph: CGFloat = OrbitTokens.Icon.regular
    var isProminent = false

    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        let snapshot = playback.snapshot
        let isPlaying = snapshot.isPlaying
        let canToggle = snapshot.track != nil && snapshot.allows(isPlaying ? .pause : .resume)
        Button {
            Task { await playback.togglePlayPause() }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .contentTransition(.symbolEffect(.replace.downUp))
                // The play triangle is optically left-heavy; nudge it so it sits centred in a disc.
                .offset(x: isPlaying || !isProminent ? 0 : 1.5)
        }
        .buttonStyle(PlaybackButtonStyle(diameter: diameter, glyph: glyph, isProminent: isProminent))
        .focusEffectDisabled()
        .disabled(!canToggle)
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityIdentifier("orbit.playPause")
    }
}

private struct PlaybackButtonStyle: ButtonStyle {
    let diameter: CGFloat
    let glyph: CGFloat
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            ProminentDisc(configuration: configuration, diameter: diameter, glyph: glyph)
        } else {
            IconButtonStyle(diameter: diameter, glyphSize: glyph).makeBody(configuration: configuration)
        }
    }
}

// The one solid control in the player: a label-colored disc with the glyph knocked out, neutral in either
// appearance so the accent stays reserved for state. Unavailable, it becomes a quiet outline-free disc with a
// secondary glyph, since a faded solid disc reads as a rendering glitch on light glass.
private struct ProminentDisc: View {
    let configuration: ButtonStyleConfiguration
    let diameter: CGFloat
    let glyph: CGFloat

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(OrbitPalette.prominentGlyph) : AnyShapeStyle(.secondary))
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(fill)
            }
            .overlay {
                if isFocused { Circle().strokeBorder(theme.accent, lineWidth: 2).padding(-3) }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !theme.reducesMotion ? 0.93 : (isHovered && !theme.reducesMotion ? 1.04 : 1))
            .onHover { hovering in isHovered = hovering && isEnabled }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .animation(theme.animation(OrbitTokens.Motion.press), value: configuration.isPressed)
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isEnabled)
    }

    private var fill: Color {
        guard isEnabled else { return OrbitPalette.quietFill(contrast: theme.contrast) }
        return OrbitPalette.prominentFill.opacity(configuration.isPressed ? 0.72 : (isHovered ? 0.86 : 1))
    }
}

struct TransportButton: View {
    let symbol: String
    let label: String
    var help: String?
    var isToggle = false
    var isOn = false
    var accessibilityValue: String?
    var isEnabled = true
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            // Toggles answer at once: the glyph swaps without a symbol effect and only the color eases.
            Image(systemName: symbol)
                .contentTransition(.identity)
        }
        .iconButton(diameter: OrbitTokens.Size.transportButton, glyph: OrbitTokens.Icon.transport, isOn: isOn, isToggle: isToggle)
        .disabled(!isEnabled)
        .help(help ?? label)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue ?? (isToggle ? (isOn ? "On" : "Off") : ""))
        .accessibilityAddTraits(isToggle ? .isToggle : [])
    }
}
