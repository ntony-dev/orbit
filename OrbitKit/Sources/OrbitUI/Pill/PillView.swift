import OrbitCore
import OrbitEngine
import SwiftUI

// The collapsed pill. Artwork sits concentric with the capsule; hovering swaps the playing indicator for compact
// transport controls. Clicks on the pill expand it, presses that travel past the drag threshold move the panel,
// and neither ever fires a control by accident.
struct PillView: View {
    let size: CGSize
    var forcesHover = false
    let onExpand: () -> Void

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    private var isCompact: Bool { size.height < OrbitTokens.Size.pill(.regular).height }
    private var artworkSize: CGFloat { isCompact ? OrbitTokens.Size.pillArtworkCompact : OrbitTokens.Size.pillArtworkRegular }
    private var inset: CGFloat { (size.height - artworkSize) / 2 }
    private var showsControls: Bool { (isHovered || forcesHover) && playback.snapshot.track != nil }

    var body: some View {
        let snapshot = playback.snapshot
        HStack(spacing: isCompact ? OrbitTokens.Spacing.m : OrbitTokens.Spacing.l - 2) {
            leadingTile(snapshot)
            titles(snapshot)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing(snapshot)
        }
        .padding(.leading, inset)
        .padding(.trailing, inset + (showsControls ? 0 : OrbitTokens.Spacing.xs))
        .frame(width: size.width, height: size.height)
        .contentShape(.capsule)
        .onTapGesture(perform: onExpand)
        .panelDraggable()
        .onHover { hovering in isHovered = hovering }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: showsControls)
        .animation(theme.animation(OrbitTokens.Motion.content), value: snapshot.track?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(snapshot))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Expand", onExpand)
        .accessibilityIdentifier("orbit.pill")
    }

    @ViewBuilder
    private func leadingTile(_ snapshot: PlaybackSnapshot) -> some View {
        if theme.showsArtwork, let track = snapshot.track {
            ArtworkView(url: track.artworkURL, size: artworkSize, cornerRadius: artworkSize / 2, keepsPrevious: true)
                .saturation(snapshot.isPlaying ? 1 : 0.6)
                .animation(theme.animation(OrbitTokens.Motion.content), value: snapshot.isPlaying)
        } else {
            Circle()
                .fill(OrbitPalette.quietFill(contrast: theme.contrast))
                .frame(width: artworkSize, height: artworkSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: artworkSize * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func titles(_ snapshot: PlaybackSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title(snapshot))
                .font(isCompact ? OrbitTokens.Typography.pillTitleCompact : OrbitTokens.Typography.pillTitleRegular)
                .foregroundStyle(snapshot.track == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
            if !isCompact, let subtitle = subtitle(snapshot) {
                Text(subtitle)
                    .font(OrbitTokens.Typography.pillSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .id(snapshot.track?.id)
        .transition(theme.reducesMotion ? .opacity : .push(from: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func trailing(_ snapshot: PlaybackSnapshot) -> some View {
        if showsControls {
            HStack(spacing: 0) {
                if !isCompact {
                    pillButton("backward.fill", label: "Previous", enabled: snapshot.allows(.skipPrevious)) {
                        await playback.previous()
                    }
                }
                PlayPauseButton(diameter: controlDiameter, glyph: OrbitTokens.Icon.regular)
                pillButton("forward.fill", label: "Next", enabled: snapshot.allows(.skipNext)) {
                    await playback.next()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
        } else if snapshot.track != nil {
            PlayingIndicator(isPlaying: snapshot.isPlaying)
                .frame(width: controlDiameter * 0.7)
                .transition(.opacity)
        }
    }

    private var controlDiameter: CGFloat { isCompact ? 26 : 30 }

    private func pillButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
        }
        .iconButton(diameter: controlDiameter, glyph: OrbitTokens.Icon.small)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func title(_ snapshot: PlaybackSnapshot) -> String {
        if let track = snapshot.track { return track.name }
        if !account.isSpotifyInstalled { return "Spotify not installed" }
        if !account.isSpotifyRunning { return "Spotify is closed" }
        return "Not playing"
    }

    private func subtitle(_ snapshot: PlaybackSnapshot) -> String? {
        if let track = snapshot.track { return track.artistLine }
        if account.authState.isSignedIn { return "Click to pick a playlist" }
        return "Click to open Orbit"
    }

    private func accessibilitySummary(_ snapshot: PlaybackSnapshot) -> String {
        guard let track = snapshot.track else { return "Orbit, \(title(snapshot))" }
        return "Orbit, \(track.name) by \(track.artistLine), \(snapshot.isPlaying ? "playing" : "paused")"
    }
}

// Breathing bars while playing, a still pause glyph otherwise. A symbol effect keeps this on the render server,
// so the always-visible pill does not tick the main thread.
struct PlayingIndicator: View {
    let isPlaying: Bool

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: isPlaying ? OrbitTokens.Icon.regular : OrbitTokens.Icon.small, weight: .semibold))
            .foregroundStyle(isPlaying ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.tertiary))
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous), isActive: isPlaying && !theme.reducesMotion)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}
