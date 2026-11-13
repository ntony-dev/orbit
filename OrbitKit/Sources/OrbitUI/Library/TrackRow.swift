import OrbitCore
import OrbitEngine
import SwiftUI

// A track in a playlist, Liked Songs, search results or the queue. Clicking plays it (inside `context` when
// there is one), or runs `action` where a click means something else, as in the queue; unplayable tracks are
// shown but disabled rather than hidden.
struct TrackRow: View {
    // What a click does instead of playing the track, named for the context menu and VoiceOver.
    struct Action {
        let title: String
        let hint: String
        let perform: () -> Void
    }

    let track: Track
    var number: Int?
    var showsArtwork = false
    var context: SpotifyURI?
    var action: Action?
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
        let showsHover = isHovered || UIDebugOptions.current.hoveredTrackID == track.id
        Button(action: perform) {
            HStack(spacing: OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs) {
                leading(isCurrent: isCurrent, showsHover: showsHover)
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
        // The queue lists what comes after the current track, so a repeat of it there is not the one playing.
        .buttonStyle(RowButtonStyle(isSelected: isCurrent && action == nil))
        .focusEffectDisabled()
        .keyboardSelected(isKeyboardSelected)
        .disabled(!track.isPlayable)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let action {
                Button(action.title, action: action.perform)
            } else {
                Button("Play", action: play)
                Button("Add to Queue") { Task { await library.addToQueue(track) } }
            }
            Divider()
            Button("Open in Spotify") { SpotifyApp.open(track.uri) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(isCurrent: isCurrent, isPending: isPending, failure: failure))
        .accessibilityHint(track.isPlayable ? action?.hint ?? "Plays this song" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityActions {
            if action == nil {
                Button("Add to Queue") { Task { await library.addToQueue(track) } }
            }
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

    // Artwork rows dim the cover and show the play glyph like a playlist's cover in the Library, so every list
    // with covers reads the same under the pointer.
    @ViewBuilder
    private func leading(isCurrent: Bool, showsHover: Bool) -> some View {
        if showsArtwork {
            ArtworkView(url: track.artworkURL, size: OrbitTokens.Size.rowArtwork - 4, cornerRadius: OrbitTokens.Radius.artworkSmall)
                .overlay {
                    if isCurrent || showsHover {
                        ZStack {
                            RoundedRectangle(cornerRadius: OrbitTokens.Radius.artworkSmall, style: .continuous)
                                .fill(.black.opacity(0.42))
                            leadingGlyph(isCurrent: isCurrent, size: OrbitTokens.Icon.regular, tint: .white)
                                .foregroundStyle(.white)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(theme.animation(OrbitTokens.Motion.hover), value: showsHover)
        } else if let number {
            ZStack {
                if isCurrent || showsHover {
                    leadingGlyph(isCurrent: isCurrent, size: OrbitTokens.Icon.small)
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
    private func leadingGlyph(isCurrent: Bool, size: CGFloat, tint: Color? = nil) -> some View {
        if isCurrent {
            PlayingIndicator(isPlaying: playback.snapshot.isPlaying, tint: tint)
        } else {
            Image(systemName: "play.fill")
                .font(.system(size: size, weight: showsArtwork ? .semibold : .regular))
        }
    }

    private func perform() {
        if let action {
            action.perform()
        } else {
            play()
        }
    }

    private func play() {
        let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
        Task { await switcher.play(track: track, in: context, with: playback, thenCollapse: collapse) }
    }
}
