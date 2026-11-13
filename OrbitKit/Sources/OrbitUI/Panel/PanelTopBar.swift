import OrbitCore
import OrbitEngine
import SwiftUI

// The strip across the top of every expanded screen. Its empty space drags the panel or, on a click, collapses
// it, and it always ends with the collapse button, so leaving the expanded surface is in the same place on every screen. One accessory (the
// player's settings, the browsing screens' play/pause) sits beside it at the same spacing everywhere.
struct PanelTopBar<Leading: View, Accessory: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let accessory: Accessory

    @Environment(PanelState.self) private var panel

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.m) {
            leading
            // The empty middle of the strip collapses on a click, like the chevron beside it; a drag across it
            // still moves the panel. Lower priority than `leading`, so it only ever takes the space left over.
            Color.clear
                .contentShape(.rect)
                .onTapGesture { panel.collapse() }
                .layoutPriority(-1)
                .accessibilityHidden(true)
            HStack(spacing: OrbitTokens.Spacing.xxs) {
                accessory
                Button {
                    panel.collapse()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .iconButton(glyph: OrbitTokens.Icon.chrome)
                // The chevron's ink, not its circle, ends on the margin the player's controls end on.
                .inkAligned(.trailing, GlyphInk.symbol("chevron.down", size: OrbitTokens.Icon.chrome), in: OrbitTokens.Size.iconButton)
                .help("Collapse")
                .accessibilityLabel("Collapse")
                .accessibilityIdentifier("orbit.collapse")
            }
        }
        .frame(height: OrbitTokens.Size.stripArtwork + OrbitTokens.Spacing.xs)
        .padding(.horizontal, OrbitTokens.Spacing.xl)
        .padding(.top, OrbitTokens.Spacing.headerTop)
        .contentShape(.rect)
        .panelDraggable()
    }
}

extension PanelTopBar where Accessory == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, accessory: { EmptyView() })
    }
}

// Settings sits on the player, the screen Orbit opens to, beside the way out, where popover utilities keep theirs;
// Command-comma reaches it from every screen.
struct SettingsButton: View {
    var body: some View {
        Button(action: OrbitSettings.open) {
            Image(systemName: "gearshape")
        }
        .iconButton(glyph: OrbitTokens.Icon.chrome)
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("orbit.settings")
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
            .iconButton(glyph: OrbitTokens.Icon.chrome)
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
        }
        .animation(theme.animation(OrbitTokens.Motion.content), value: snapshot.track?.id)
    }

    // The strip's play/pause, placed in the top bar's accessory slot beside the collapse button.
    struct PlayPause: View {
        @Environment(PlaybackCoordinator.self) private var playback

        var body: some View {
            if playback.snapshot.track != nil {
                PlayPauseButton(diameter: OrbitTokens.Size.iconButton, glyph: OrbitTokens.Icon.regular, isProminent: false)
            }
        }
    }
}
