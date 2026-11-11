import OrbitCore
import OrbitEngine
import SwiftUI

// The strip across the top of every expanded screen. Its empty space drags the panel, and it always ends with
// the collapse button, so leaving the expanded surface is in the same place on every screen.
struct PanelTopBar<Leading: View>: View {
    @ViewBuilder let leading: Leading

    @Environment(PanelState.self) private var panel

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.m) {
            leading
            Spacer(minLength: 0)
            Button {
                panel.collapse()
            } label: {
                Image(systemName: "chevron.down")
            }
            .iconButton(glyph: OrbitTokens.Icon.small)
            .help("Collapse")
            .accessibilityLabel("Collapse")
            .accessibilityIdentifier("orbit.collapse")
        }
        .frame(height: OrbitTokens.Size.stripArtwork + OrbitTokens.Spacing.xs)
        .padding(.leading, OrbitTokens.Spacing.xl)
        .padding(.trailing, OrbitTokens.Spacing.l)
        .padding(.top, OrbitTokens.Spacing.l + OrbitTokens.Spacing.xxs)
        .contentShape(.rect)
        .panelDraggable()
    }
}

struct BackTitle: View {
    let title: String
    var subtitle: String?

    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.xs) {
            Button {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { _ = navigator.back() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .iconButton(glyph: OrbitTokens.Icon.regular)
            .padding(.leading, -OrbitTokens.Spacing.m)
            .help("Back")
            .accessibilityLabel("Back")
            .keyboardShortcut("[", modifiers: .command)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(OrbitTokens.Typography.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(OrbitTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// A compact now-playing line for screens other than the player: playback stays one click away while browsing,
// and clicking the track returns to the player.
struct NowPlayingStrip: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        let snapshot = playback.snapshot
        HStack(spacing: OrbitTokens.Spacing.m) {
            Button {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.show(.player) }
            } label: {
                HStack(spacing: OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs) {
                    ArtworkView(
                        url: theme.showsArtwork ? snapshot.track?.artworkURL : nil,
                        size: OrbitTokens.Size.stripArtwork,
                        cornerRadius: OrbitTokens.Radius.artworkSmall,
                        keepsPrevious: true
                    )
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.track?.name ?? "Not Playing")
                            .font(OrbitTokens.Typography.captionEmphasized)
                            .lineLimit(1)
                        Text(snapshot.track?.artistLine ?? "Choose something to play")
                            .font(OrbitTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentTransition(.opacity)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Show Now Playing")
            .accessibilityLabel(snapshot.track.map { "Now playing: \($0.name) by \($0.artistLine)" } ?? "Not playing")
            .accessibilityHint("Shows the player")
            if snapshot.track != nil {
                PlayPauseButton(diameter: OrbitTokens.Size.iconButton, glyph: OrbitTokens.Icon.regular, isProminent: false)
            }
        }
        .animation(theme.animation(OrbitTokens.Motion.content), value: snapshot.track?.id)
    }
}
