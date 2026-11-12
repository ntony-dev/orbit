import OrbitCore
import OrbitEngine
import SwiftUI

// One playlist in the picker or library. In the picker a click switches playback; in the library it opens the
// playlist and a hover button plays it. Pending, failed, confirmed and current states are all visible on the row.
struct PlaylistRow: View {
    enum Behavior {
        case switchOnClick, browse
    }

    let playlist: Playlist
    var behavior: Behavior = .switchOnClick
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
        Button(action: primaryAction) {
            HStack(spacing: OrbitTokens.Spacing.l) {
                PlaylistArtwork(playlist: playlist, size: OrbitTokens.Size.rowArtwork)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.name)
                        .font(OrbitTokens.Typography.rowTitle)
                        .lineLimit(1)
                    subtitle(status)
                }
                Spacer(minLength: OrbitTokens.Spacing.s)
                trailing(status)
                    .frame(minWidth: 20)
            }
            .padding(.horizontal, OrbitTokens.Spacing.m)
            .frame(height: OrbitTokens.Size.rowHeight)
        }
        .rowButton(isSelected: status.isCurrent)
        .onHover { isHovered = $0 }
        .animation(theme.animation(OrbitTokens.Motion.content), value: status)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(status))
        .accessibilityHint(behavior == .browse ? "Shows its tracks" : "Plays this playlist")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(status.isCurrent ? .isSelected : [])
        .accessibilityActions {
            if behavior == .browse {
                Button("Play", action: switchPlayback)
            } else {
                Button("Show Tracks", action: showTracks)
            }
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

    @ViewBuilder
    private func trailing(_ status: PlaylistRowStatus) -> some View {
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
        } else if behavior == .browse {
            HStack(spacing: OrbitTokens.Spacing.xs) {
                if isHovered && !status.isCurrent {
                    Button(action: switchPlayback) {
                        Image(systemName: "play.fill")
                    }
                    .iconButton(diameter: 24, glyph: OrbitTokens.Icon.small)
                    .help("Play \(playlist.name)")
                    .accessibilityLabel("Play \(playlist.name)")
                    .transition(.opacity)
                } else if status.isCurrent {
                    PlayingIndicator(isPlaying: status.isPlaying)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: OrbitTokens.Icon.small - 1, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
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
        Button(behavior == .browse ? "Play" : "Play Now", action: switchPlayback)
        if behavior == .switchOnClick {
            Button("Show Tracks", action: showTracks)
        }
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

    private func primaryAction() {
        switch behavior {
        case .switchOnClick:
            switchPlayback()
        case .browse:
            withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.push(.playlist(playlist)) }
        }
    }

    private func showTracks() {
        withAnimation(theme.animation(OrbitTokens.Motion.navigate)) {
            navigator.showLibrary(.playlists)
            navigator.push(.playlist(playlist))
        }
    }

    private func togglePin() {
        withAnimation(theme.animation(OrbitTokens.Motion.content)) {
            library.isPinned(playlist) ? library.unpin(playlist) : library.pin(playlist)
        }
    }

    private func switchPlayback() {
        let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
        Task { await switcher.play(playlist, with: playback, thenCollapse: collapse) }
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
