import OrbitCore
import OrbitEngine
import SwiftUI

// A track in a playlist, Liked Songs, search results or the queue. Clicking plays it (inside `context` when
// there is one); unplayable tracks are shown but disabled rather than hidden.
struct TrackRow: View {
    let track: Track
    var number: Int?
    var showsArtwork = false
    var context: SpotifyURI?
    var isInteractive = true
    var isKeyboardSelected = false

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        let isCurrent = playback.snapshot.track?.uri == track.uri
        let isPending = playback.pendingIntents.contains(.playTrack(track.uri)) || playback.pendingIntents.contains(.playContext(track.uri))
        let failure = switcher.failure(for: track.uri)
        Button(action: play) {
            HStack(spacing: OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs) {
                leading(isCurrent: isCurrent)
                VStack(alignment: .leading, spacing: 1) {
                    // The current track is marked by its row tint and the playing bars; an accent-coloured title
                    // would wash out with the neutral accent on a light desktop.
                    Text(track.name)
                        .font(OrbitTokens.Typography.rowTitle)
                        .lineLimit(1)
                    HStack(spacing: OrbitTokens.Spacing.xs) {
                        if track.isExplicit {
                            Image(systemName: "e.square.fill")
                                .font(.system(size: OrbitTokens.Icon.small - 1))
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Explicit")
                        }
                        if let failure {
                            Text("Couldn't play · \(failure.message)")
                                .foregroundStyle(OrbitPalette.warning)
                        } else {
                            Text(track.isPlayable ? track.artistLine : "Unavailable · \(track.artistLine)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(OrbitTokens.Typography.caption)
                    .lineLimit(1)
                }
                Spacer(minLength: OrbitTokens.Spacing.s)
                if isPending {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(Formatting.time(track.duration))
                        .font(OrbitTokens.Typography.timecode)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, OrbitTokens.Spacing.m)
            .frame(height: showsArtwork ? OrbitTokens.Size.artworkTrackRowHeight : OrbitTokens.Size.trackRowHeight)
        }
        .buttonStyle(RowButtonStyle(isSelected: isCurrent && isInteractive))
        .focusEffectDisabled()
        .keyboardSelected(isKeyboardSelected)
        .allowsHitTesting(isInteractive)
        .disabled(!track.isPlayable)
        .onHover { isHovered = $0 && isInteractive }
        .contextMenu {
            if isInteractive { Button("Play", action: play) }
            Button("Add to Queue") { Task { await library.addToQueue(track) } }
            Divider()
            Button("Open in Spotify") { SpotifyApp.open(track.uri) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(isCurrent: isCurrent, isPending: isPending, failure: failure))
        .accessibilityHint(isInteractive && track.isPlayable ? "Plays this song" : "")
        .accessibilityAddTraits(isInteractive ? .isButton : [])
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityActions {
            Button("Add to Queue") { Task { await library.addToQueue(track) } }
            Button("Open in Spotify") { SpotifyApp.open(track.uri) }
        }
    }

    private func accessibilityLabel(isCurrent: Bool, isPending: Bool, failure: OrbitError?) -> String {
        var parts = [track.name, track.artistLine, Formatting.time(track.duration)]
        if let number { parts.insert("\(number)", at: 0) }
        if track.isExplicit { parts.append("explicit") }
        if !track.isPlayable { parts.append("unavailable") }
        if isPending { parts.append("starting") }
        if let failure { parts.append("couldn't play: \(failure.message)") }
        if isCurrent { parts.append(playback.snapshot.isPlaying ? "now playing" : "paused") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func leading(isCurrent: Bool) -> some View {
        if showsArtwork {
            ArtworkView(url: track.artworkURL, size: OrbitTokens.Size.rowArtwork - 4, cornerRadius: OrbitTokens.Radius.artworkSmall)
                .overlay {
                    if isCurrent || isHovered {
                        RoundedRectangle(cornerRadius: OrbitTokens.Radius.artworkSmall, style: .continuous)
                            .fill(.black.opacity(0.38))
                        leadingGlyph(isCurrent: isCurrent, tint: .white)
                            .foregroundStyle(.white)
                    }
                }
        } else if let number {
            ZStack {
                if isCurrent || isHovered {
                    leadingGlyph(isCurrent: isCurrent)
                } else {
                    Text("\(number)")
                        .font(OrbitTokens.Typography.timecode)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 22)
        }
    }

    @ViewBuilder
    private func leadingGlyph(isCurrent: Bool, tint: Color? = nil) -> some View {
        if isCurrent {
            PlayingIndicator(isPlaying: playback.snapshot.isPlaying, tint: tint)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: OrbitTokens.Icon.small))
        }
    }

    private func play() {
        guard isInteractive else { return }
        let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
        Task { await switcher.play(track: track, in: context, with: playback, thenCollapse: collapse) }
    }
}
