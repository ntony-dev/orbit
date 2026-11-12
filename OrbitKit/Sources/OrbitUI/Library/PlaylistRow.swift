import OrbitCore
import OrbitEngine
import SwiftUI

// One playlist in the library. Switching playlists is what Orbit is for, so the whole row plays it on one click;
// the chevron at its end, always visible, opens its tracks. Pending, failed, confirmed and current states are all
// visible on the row, and the playing row keeps its equalizer beside the chevron.
struct PlaylistRow: View {
    let playlist: Playlist
    var isRecent = false

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    private var status: PlaylistRowStatus {
        PlaylistRowStatus(
            isCurrent: playback.snapshot.context?.uri == playlist.uri,
            isPlaying: playback.snapshot.isPlaying,
            isPending: playback.pendingIntents.contains(.playContext(playlist.uri)),
            isConfirmed: switcher.confirmed == playlist.uri,
            failure: switcher.failure(for: playlist.uri),
            isMissing: library.missingPlaylistIDs.contains(playlist.id)
        )
    }

    var body: some View {
        let status = status
        Button(action: switchPlayback) {
            HStack(spacing: OrbitTokens.Spacing.l) {
                PlaylistArtwork(playlist: playlist, size: OrbitTokens.Size.rowArtwork)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.name)
                        .font(OrbitTokens.Typography.rowTitle)
                        .lineLimit(1)
                    subtitle(status)
                }
                Spacer(minLength: OrbitTokens.Spacing.s)
                HStack(spacing: OrbitTokens.Spacing.xxs) {
                    indicator(status)
                        .frame(minWidth: OrbitTokens.Size.playingIndicator)
                    ShowTracksButton(playlist: playlist, action: showTracks)
                }
            }
            .padding(.leading, OrbitTokens.Spacing.m)
            .padding(.trailing, OrbitTokens.Spacing.xs)
            .frame(height: OrbitTokens.Size.rowHeight)
        }
        .rowButton(isSelected: status.isCurrent)
        .onHover { isHovered = $0 }
        .animation(theme.animation(OrbitTokens.Motion.content), value: status)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(status))
        .accessibilityHint("Plays this playlist")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(status.isCurrent ? .isSelected : [])
        .accessibilityActions {
            Button("Show Tracks", action: showTracks)
            Button(library.isPinned(playlist) ? "Unpin" : "Pin", action: togglePin)
            if isRecent {
                Button("Remove from Recents") { library.removeRecent(playlist) }
            }
            Button("Open in Spotify") { SpotifyApp.open(playlist.uri) }
        }
    }

    @ViewBuilder
    private func subtitle(_ status: PlaylistRowStatus) -> some View {
        Group {
            if let failure = status.failure {
                Text("Couldn't switch · \(failure.message)")
                    .foregroundStyle(OrbitPalette.warning)
            } else if status.isPending {
                Text("Starting…")
                    .foregroundStyle(.secondary)
            } else if status.isMissing {
                Text("No longer available on Spotify")
                    .foregroundStyle(.secondary)
            } else if status.isCurrent {
                Text(status.isPlaying ? "Now playing" : "Paused")
                    .foregroundStyle(theme.accent)
            } else {
                Text(Formatting.playlistSubtitle(playlist))
                    .foregroundStyle(.secondary)
            }
        }
        .font(OrbitTokens.Typography.caption)
        .lineLimit(1)
        .contentTransition(.opacity)
    }

    // What the row says about playback, beside the chevron; hovering previews the click with a play glyph.
    @ViewBuilder
    private func indicator(_ status: PlaylistRowStatus) -> some View {
        if status.isPending {
            ProgressView()
                .controlSize(.mini)
                .transition(.opacity)
        } else if status.failure != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: OrbitTokens.Icon.regular))
                .foregroundStyle(OrbitPalette.warning)
                .help("Click to try again")
                .transition(.opacity)
        } else if status.isConfirmed {
            Image(systemName: "checkmark")
                .font(.system(size: OrbitTokens.Icon.regular, weight: .bold))
                .foregroundStyle(theme.accent)
                .transition(theme.reducesMotion ? .opacity : .scale.combined(with: .opacity))
        } else if status.isCurrent {
            PlayingIndicator(isPlaying: status.isPlaying)
        } else if isHovered {
            Image(systemName: "play.fill")
                .font(.system(size: OrbitTokens.Icon.small))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        } else if library.isPinned(playlist) && !LikedSongs.contains(playlist) {
            Image(systemName: "pin.fill")
                .font(.system(size: OrbitTokens.Icon.small - 2))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(35))
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Play", action: switchPlayback)
        Button("Show Tracks", action: showTracks)
        Divider()
        if library.isPinned(playlist) {
            Button("Unpin", action: togglePin)
            if let index = library.pinnedPlaylists.firstIndex(where: { $0.id == playlist.id }) {
                Button("Move Up") { movePinned(from: index, by: -1) }
                    .disabled(index == 0)
                Button("Move Down") { movePinned(from: index, by: 1) }
                    .disabled(index == library.pinnedPlaylists.count - 1)
            }
        } else {
            Button("Pin to Top", action: togglePin)
        }
        if isRecent {
            Button("Remove from Recents") {
                withAnimation(theme.animation(OrbitTokens.Motion.content)) { library.removeRecent(playlist) }
            }
        }
        Divider()
        Button("Open in Spotify") { SpotifyApp.open(playlist.uri) }
    }

    private func showTracks() {
        withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.push(.playlist(playlist)) }
    }

    private func togglePin() {
        withAnimation(theme.animation(OrbitTokens.Motion.content)) {
            library.isPinned(playlist) ? library.unpin(playlist) : library.pin(playlist)
        }
    }

    private func switchPlayback() {
        Task { await switcher.play(playlist, with: playback, thenCollapse: panel.collapseAfterAction(preferences)) }
    }

    private func movePinned(from index: Int, by offset: Int) {
        let destination = offset < 0 ? index - 1 : index + 2
        withAnimation(theme.animation(OrbitTokens.Motion.content)) {
            library.movePinned(fromOffsets: IndexSet(integer: index), toOffset: destination)
        }
    }

    private func accessibilityLabel(_ status: PlaylistRowStatus) -> String {
        var parts = [playlist.name, Formatting.playlistSubtitle(playlist)]
        if library.isPinned(playlist) && !LikedSongs.contains(playlist) { parts.append("pinned") }
        if status.isMissing { parts.append("no longer available") }
        if status.isPending { parts.append("starting") }
        if let failure = status.failure { parts.append("couldn't switch: \(failure.message)") }
        if status.isCurrent { parts.append(status.isPlaying ? "now playing" : "paused") }
        return parts.joined(separator: ", ")
    }
}

// The row's second action: a full-size icon button, so opening a playlist is as easy to hit as playing it, and
// quiet at rest, so the row still reads as one target that plays.
private struct ShowTracksButton: View {
    let playlist: Playlist
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
        }
        .iconButton(glyph: OrbitTokens.Icon.small, recedesAtRest: true)
        .help("Show Tracks")
        .accessibilityLabel("Show tracks of \(playlist.name)")
    }
}

struct PlaylistRowStatus: Equatable {
    var isCurrent: Bool
    var isPlaying: Bool
    var isPending: Bool
    var isConfirmed: Bool
    var failure: OrbitError?
    var isMissing = false
}

struct PlaylistArtwork: View {
    let playlist: Playlist
    let size: CGFloat
    var cornerRadius: CGFloat = OrbitTokens.Radius.artwork

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        if LikedSongs.contains(playlist) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.accent.opacity(theme.isHighContrast ? 0.3 : 0.18))
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .frame(width: size, height: size)
        } else {
            ArtworkView(url: playlist.artworkURL, size: size, cornerRadius: cornerRadius, placeholderSymbol: "music.note.list")
        }
    }
}
