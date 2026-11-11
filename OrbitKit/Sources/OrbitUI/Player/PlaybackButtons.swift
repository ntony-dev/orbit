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
// appearance so the accent stays reserved for state.
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
            .foregroundStyle(OrbitPalette.prominentGlyph)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(OrbitPalette.prominentFill.opacity(configuration.isPressed ? 0.72 : (isHovered ? 0.86 : 1)))
            }
            .overlay {
                if isFocused { Circle().strokeBorder(theme.accent, lineWidth: 2).padding(-3) }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !theme.reducesMotion ? 0.93 : (isHovered && !theme.reducesMotion ? 1.04 : 1))
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { hovering in isHovered = hovering && isEnabled }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .animation(theme.animation(OrbitTokens.Motion.press), value: configuration.isPressed)
    }
}

struct TransportButton: View {
    let symbol: String
    let label: String
    var isOn = false
    var isEnabled = true
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
        }
        .iconButton(diameter: OrbitTokens.Size.transportButton, glyph: OrbitTokens.Icon.transport, isOn: isOn)
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "")
    }
}
