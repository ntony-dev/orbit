import OrbitCore
import OrbitEngine
import SwiftUI

// A playlist's contents. Spotify only returns items for playlists the user owns or collaborates on; for the rest
// this says so plainly and keeps playing the playlist one click away, rather than showing an empty list.
struct PlaylistDetailView: View {
    let playlist: Playlist

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var selection = KeyboardSelection()
    // The playing track's row, scrolled to the middle once when it arrives, which may be on a later page.
    @State private var arrival: String?
    // Once the user scrolls, a later page holding the playing track no longer pulls the list to it.
    @State private var hasScrolled = false

    private var isLiked: Bool { LikedSongs.contains(playlist) }

    private var tracks: LoadState<[Track]> {
        isLiked ? library.savedTracks : library.items(for: playlist)
    }

    private var remaining: RemainingPages? {
        library.remainingPages(for: playlist)
    }

    var body: some View {
        let loaded = tracks.value ?? []
        let keys = loaded.indices.map { "row:\($0)" }
        VStack(spacing: 0) {
            PanelTopBar { BackTitle(title: "Library") }
            // Spotify's count until every page is in, so the subtitle never counts up as pages land.
            PlaylistHeader(playlist: playlist, trackCount: remaining == nil ? tracks.value?.count : (isLiked ? library.likedSongsCount : nil))
                .padding(.horizontal, OrbitTokens.Spacing.xl)
                .padding(.top, OrbitTokens.Spacing.xs)
                .padding(.bottom, OrbitTokens.Spacing.m)
            Rectangle()
                .fill(OrbitPalette.separator(contrast: theme.contrast))
                .frame(height: 0.5)
                .padding(.horizontal, OrbitTokens.Spacing.xl)
            PanelScroll(reveal: selection.key ?? arrival, revealAnchor: selection.key == nil ? .center : nil, onUserScroll: { hasScrolled = true }) {
                content
            }
            .keyboardList(selection: $selection, keys: keys) { key in
                guard let index = keys.firstIndex(of: key), loaded[index].isPlayable else { return }
                Task {
                    await switcher.play(track: loaded[index], in: playlist.uri, with: playback, thenCollapse: panel.collapseAfterAction(preferences))
                }
            }
        }
        .task(id: playlist.id) { await load(force: false) }
        // Checked again as each page lands, so a playing track on a later page is still scrolled to.
        .onChange(of: loaded.count, initial: true) {
            guard arrival == nil, !hasScrolled, selection.key == nil, let current = playback.snapshot.track?.uri,
                  let index = loaded.firstIndex(where: { $0.uri == current })
            else { return }
            arrival = keys[index]
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tracks {
        case .idle, .loading:
            SkeletonRows(count: 6, artwork: false)
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.top, OrbitTokens.Spacing.s)
        case .failed(.playlistItemsUnavailable):
            RestrictedPlaylistMessage(playlist: playlist)
                .listState()
        case .failed(let error):
            StatusMessage(error: error) { Task { await load(force: true) } }
                .listState()
        case .loaded(let tracks) where tracks.isEmpty:
            StatusMessage(
                symbol: isLiked ? "heart" : "music.note.list",
                title: isLiked ? "No liked songs yet" : "This playlist is empty",
                message: isLiked ? "Tap the heart in the player to save a song." : nil
            )
            .listState()
        case .loaded(let tracks):
            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    TrackRow(track: track, number: index + 1, context: playlist.uri, isKeyboardSelected: selection.key == "row:\(index)")
                        .id("row:\(index)")
                }
                remainingFooter
            }
            .padding(.horizontal, OrbitTokens.Spacing.m)
            .padding(.vertical, OrbitTokens.Spacing.s)
        }
    }

    // Below the rows already shown: placeholders while later pages load, and a way to continue when one fails.
    @ViewBuilder
    private var remainingFooter: some View {
        switch remaining {
        case .loading:
            SkeletonRows(count: 3, artwork: false)
                .padding(.top, OrbitTokens.Spacing.xs)
        case .failed(let error):
            StatusMessage(error: error) { Task { await library.loadItems(for: playlist) } }
                .padding(.vertical, OrbitTokens.Spacing.l)
        case nil:
            EmptyView()
        }
    }

    private func load(force: Bool) async {
        // A list whose later pages failed continues when it is shown again, whatever the error offered.
        let continues = if case .failed = remaining { true } else { false }
        if !force, !continues, tracks.value != nil || tracks.isLoading { return }
        if isLiked {
            await library.loadSavedTracks()
        } else {
            await library.loadItems(for: playlist)
        }
    }
}

private struct PlaylistHeader: View {
    let playlist: Playlist
    let trackCount: Int?

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        var shown = playlist
        if let trackCount { shown.itemCount = trackCount }
        let isCurrent = playback.snapshot.context?.uri == playlist.uri
        let isPending = playback.pendingIntents.contains(.playContext(playlist.uri))
        let failure = switcher.failure(for: playlist.uri)
        return HStack(alignment: .center, spacing: OrbitTokens.Spacing.l + OrbitTokens.Spacing.xxs) {
            PlaylistArtwork(playlist: playlist, size: OrbitTokens.Size.detailArtwork, cornerRadius: OrbitTokens.Radius.artworkLarge - 2)
            VStack(alignment: .leading, spacing: OrbitTokens.Spacing.xxs) {
                Text(playlist.name)
                    .font(OrbitTokens.Typography.title)
                    .lineLimit(2)
                Text(failure.map { "Couldn't play · \($0.message)" } ?? Formatting.playlistSubtitle(shown))
                    .font(OrbitTokens.Typography.caption)
                    .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(OrbitPalette.warning))
                    .lineLimit(1)
                HStack(spacing: OrbitTokens.Spacing.s) {
                    PlaylistPlayButton(isCurrent: isCurrent, isPending: isPending, hasFailed: failure != nil) {
                        isCurrent ? togglePlayback() : play()
                    }
                    Button {
                        withAnimation(theme.animation(OrbitTokens.Motion.content)) {
                            library.isPinned(playlist) ? library.unpin(playlist) : library.pin(playlist)
                        }
                    } label: {
                        Image(systemName: library.isPinned(playlist) ? "pin.fill" : "pin")
                    }
                    .iconButton(isOn: library.isPinned(playlist), showsOnIndicator: false)
                    .help(library.isPinned(playlist) ? "Unpin" : "Pin to Top of Library")
                    .accessibilityLabel(library.isPinned(playlist) ? "Unpin \(playlist.name)" : "Pin \(playlist.name)")
                    .accessibilityHint("Pinned playlists stay at the top of the library")
                    Button {
                        SpotifyApp.open(playlist.uri)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .iconButton()
                    .help("Open in Spotify")
                    .accessibilityLabel("Open in Spotify")
                }
                .padding(.top, OrbitTokens.Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func play() {
        Task { await switcher.play(playlist, with: playback, thenCollapse: panel.collapseAfterAction(preferences)) }
    }

    private func togglePlayback() {
        Task { await playback.togglePlayPause() }
    }
}

private struct PlaylistPlayButton: View {
    let isCurrent: Bool
    let isPending: Bool
    let hasFailed: Bool
    let action: () -> Void

    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        Button(action: action) {
            if isPending {
                HStack(spacing: OrbitTokens.Spacing.s) {
                    ProgressView().controlSize(.mini)
                    Text("Starting")
                }
            } else if isCurrent {
                let isPlaying = playback.snapshot.isPlaying
                Label(isPlaying ? "Pause" : "Resume", systemImage: isPlaying ? "pause.fill" : "play.fill")
            } else {
                Label(hasFailed ? "Try Again" : "Play", systemImage: hasFailed ? "arrow.clockwise" : "play.fill")
            }
        }
        .capsuleButton(prominent: !isCurrent)
        .disabled(isPending)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isPending { return "Starting playlist" }
        if isCurrent { return playback.snapshot.isPlaying ? "Pause playlist" : "Resume playlist" }
        return hasFailed ? "Try playing the playlist again" : "Play playlist"
    }
}

struct RestrictedPlaylistMessage: View {
    let playlist: Playlist

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences

    var body: some View {
        StatusMessage(
            symbol: "lock",
            title: "Tracks aren't available for this playlist",
            message: "Spotify only shares the tracks of playlists you own or collaborate on. You can still play it.",
            actions: [
                StateAction(title: "Play Playlist", symbol: "play.fill") {
                    let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
                    Task { await switcher.play(playlist, with: playback, thenCollapse: collapse) }
                },
                StateAction(title: "Open in Spotify", isProminent: false) { SpotifyApp.open(playlist.uri) },
            ]
        )
    }
}
