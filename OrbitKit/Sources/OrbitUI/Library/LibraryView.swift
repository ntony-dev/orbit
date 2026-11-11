import OrbitCore
import OrbitEngine
import SwiftUI

// The mini library: denser than the picker, with playlists to browse into, Liked Songs, the queue and Spotify
// search. The now-playing strip above keeps the way back to the player in view.
struct LibraryView: View {
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        @Bindable var navigator = navigator
        VStack(spacing: 0) {
            PanelTopBar { NowPlayingStrip() }
            AccountGate {
                VStack(spacing: 0) {
                    ChipTabs(
                        tabs: [
                            Segment(value: LibraryTab.playlists, title: "Playlists", symbol: "music.note.list"),
                            Segment(value: LibraryTab.liked, title: "Liked", symbol: "heart"),
                            Segment(value: LibraryTab.queue, title: "Queue", symbol: "list.bullet"),
                            Segment(value: LibraryTab.search, title: "Search", symbol: "magnifyingglass"),
                        ],
                        selection: $navigator.libraryTab
                    )
                    .padding(.horizontal, OrbitTokens.Spacing.xl)
                    .padding(.top, OrbitTokens.Spacing.m)
                    ZStack(alignment: .top) {
                        tab
                            .id(navigator.libraryTab)
                            .transition(.opacity)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var tab: some View {
        switch navigator.libraryTab {
        case .playlists: LibraryPlaylistsTab()
        case .liked: LikedSongsTab()
        case .queue: QueueTab()
        case .search: SearchTab()
        }
    }
}

// Lighter than SegmentedControl so a second row of navigation inside the library reads as a filter, not as a
// competing set of sections.
struct ChipTabs<Value: Hashable>: View {
    let tabs: [Segment<Value>]
    @Binding var selection: Value

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            ForEach(tabs) { tab in
                let isSelected = tab.value == selection
                Button {
                    withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { selection = tab.value }
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .labelStyle(ChipLabelStyle(showsIcon: tab.symbol == "magnifyingglass"))
                        .font(OrbitTokens.Typography.caption.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs)
                        .frame(height: 24)
                        .background {
                            Capsule().fill(isSelected
                                ? theme.accent.opacity(theme.isHighContrast ? 0.32 : 0.2)
                                : OrbitPalette.quietFill(contrast: theme.contrast))
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// Chips read as text filters; only Search keeps its glyph, since it changes what the field below does.
private struct ChipLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OrbitTokens.Spacing.xs) {
            if showsIcon { configuration.icon.imageScale(.small) }
            configuration.title
        }
    }
}

private struct LibraryPlaylistsTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchField(prompt: "Filter your playlists", text: $filter) {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { _ = navigator.back() }
            }
            .padding(.horizontal, OrbitTokens.Spacing.xl)
            .padding(.vertical, OrbitTokens.Spacing.m)
            switch library.playlists {
            case .idle, .loading:
                SkeletonRows(count: 6)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.loadPlaylists() } }
                    .frame(maxHeight: .infinity)
            case .loaded(let playlists):
                let liked = LikedSongs.playlist(for: account.profile, count: library.savedTracks.value?.count)
                let shown = ([liked].compactMap { $0 } + playlists).filter {
                    filter.isEmpty || $0.name.localizedStandardContains(filter.trimmingCharacters(in: .whitespaces))
                }
                if shown.isEmpty {
                    StatusMessage(symbol: "magnifyingglass", title: "No playlists match “\(filter)”")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                            ForEach(shown) { playlist in
                                PlaylistRow(playlist: playlist, behavior: .browse)
                            }
                        }
                        .padding(.horizontal, OrbitTokens.Spacing.m)
                        .padding(.bottom, OrbitTokens.Spacing.m)
                    }
                    .scrollEdgeEffectStyle(.soft, for: .vertical)
                }
            }
        }
        .task {
            if case .idle = library.playlists { await library.loadPlaylists() }
        }
    }
}

private struct LikedSongsTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account

    var body: some View {
        let context = LikedSongs.playlist(for: account.profile, count: nil)?.uri
        Group {
            switch library.savedTracks {
            case .idle, .loading:
                SkeletonRows(count: 7)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.top, OrbitTokens.Spacing.m)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.loadSavedTracks() } }
                    .frame(maxHeight: .infinity)
            case .loaded(let tracks) where tracks.isEmpty:
                StatusMessage(symbol: "heart", title: "No liked songs yet", message: "Tap the heart in the player to save a song.")
                    .frame(maxHeight: .infinity)
            case .loaded(let tracks):
                ScrollView {
                    LazyVStack(spacing: 0) {
                        SectionHeader(title: "Liked Songs", trailing: Formatting.songCount(tracks.count))
                        ForEach(tracks) { track in
                            TrackRow(track: track, showsArtwork: true, context: context)
                        }
                    }
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.bottom, OrbitTokens.Spacing.m)
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
        .task {
            if case .idle = library.savedTracks { await library.loadSavedTracks() }
        }
    }
}

private struct QueueTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var retained: PlaybackQueue?

    var body: some View {
        Group {
            switch library.queue.retaining(retained) {
            case .idle, .loading:
                SkeletonRows(count: 6)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.top, OrbitTokens.Spacing.m)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.loadQueue() } }
                    .frame(maxHeight: .infinity)
            case .loaded(let queue):
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let current = queue.current {
                            SectionHeader(title: "Now Playing")
                            TrackRow(track: current, showsArtwork: true, isInteractive: false)
                        }
                        SectionHeader(title: "Next Up", trailing: queue.upcoming.isEmpty ? nil : Formatting.songCount(queue.upcoming.count))
                        if queue.upcoming.isEmpty {
                            StatusMessage(
                                symbol: "text.line.first.and.arrowtriangle.forward",
                                title: "Nothing queued",
                                message: "Right-click a song anywhere in Orbit and choose Add to Queue."
                            )
                            .padding(.vertical, OrbitTokens.Spacing.xxl)
                        }
                        ForEach(Array(queue.upcoming.enumerated()), id: \.offset) { _, track in
                            TrackRow(track: track, showsArtwork: true, isInteractive: false)
                        }
                    }
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.bottom, OrbitTokens.Spacing.m)
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
        .onChange(of: library.queue.value, initial: true) { _, value in
            if let value { retained = value }
        }
        // Reloaded on each track change, which is when the queue actually moves; there is no polling.
        .task(id: playback.snapshot.track?.id) {
            await library.loadQueue()
        }
    }
}

private struct SearchTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var retained: SearchResults?

    var body: some View {
        @Bindable var navigator = navigator
        VStack(spacing: 0) {
            SearchField(prompt: "Search songs, albums, playlists", text: $navigator.searchQuery, focusOnAppear: true) {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { _ = navigator.back() }
            }
            .padding(.horizontal, OrbitTokens.Spacing.xl)
            .padding(.vertical, OrbitTokens.Spacing.m)
            results
        }
        .onChange(of: library.searchResults.value, initial: true) { _, value in
            if let value { retained = value }
        }
        .task(id: navigator.searchQuery) {
            let query = navigator.searchQuery
            guard query != library.searchQuery || library.searchResults.value == nil else { return }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                try? await Task.sleep(for: OrbitTokens.Motion.searchDebounce)
                guard !Task.isCancelled else { return }
            }
            await library.search(query)
        }
    }

    @ViewBuilder
    private var results: some View {
        let query = navigator.searchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            StatusMessage(symbol: "magnifyingglass", title: "Search Spotify", message: "Find songs, albums and playlists to play right away.")
                .frame(maxHeight: .infinity)
        } else {
            switch library.searchResults.retaining(retained) {
            case .idle, .loading:
                SkeletonRows(count: 6)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.search(navigator.searchQuery) } }
                    .frame(maxHeight: .infinity)
            case .loaded(let results) where results.isEmpty:
                StatusMessage(symbol: "magnifyingglass", title: "No results for “\(query)”", message: "Check the spelling or try fewer words.")
                    .frame(maxHeight: .infinity)
            case .loaded(let results):
                ScrollView {
                    LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                        if !results.tracks.isEmpty {
                            SectionHeader(title: "Songs")
                            ForEach(results.tracks) { track in
                                TrackRow(track: track, showsArtwork: true)
                            }
                        }
                        if !results.playlists.isEmpty {
                            SectionHeader(title: "Playlists")
                            ForEach(results.playlists) { playlist in
                                PlaylistRow(playlist: playlist, behavior: .browse)
                            }
                        }
                        if !results.albums.isEmpty {
                            SectionHeader(title: "Albums")
                            ForEach(results.albums) { album in
                                AlbumRow(album: album)
                            }
                        }
                    }
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.bottom, OrbitTokens.Spacing.m)
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
        }
    }
}

private struct AlbumRow: View {
    let album: Album

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        let isCurrent = playback.snapshot.context?.uri == album.uri
        let isPending = playback.pendingIntents.contains(.playContext(album.uri))
        let failure = switcher.failure(for: album.uri)
        Button(action: play) {
            HStack(spacing: OrbitTokens.Spacing.l) {
                ArtworkView(url: album.artworkURL, size: OrbitTokens.Size.rowArtwork, placeholderSymbol: "square.stack")
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name)
                        .font(OrbitTokens.Typography.rowTitle)
                        .lineLimit(1)
                    Text(failure.map { "Couldn't play · \($0.message)" } ?? "Album · \(album.artists.joined(separator: ", "))")
                        .font(OrbitTokens.Typography.caption)
                        .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(OrbitPalette.warning))
                        .lineLimit(1)
                }
                Spacer(minLength: OrbitTokens.Spacing.s)
                if isPending {
                    ProgressView().controlSize(.mini)
                } else if isCurrent {
                    PlayingIndicator(isPlaying: playback.snapshot.isPlaying)
                }
            }
            .padding(.horizontal, OrbitTokens.Spacing.m)
            .frame(height: OrbitTokens.Size.rowHeight)
        }
        .rowButton(isSelected: isCurrent)
        .contextMenu {
            Button("Play", action: play)
            Button("Open in Spotify") { SpotifyApp.open(album.uri) }
        }
        .accessibilityLabel("\(album.name), album by \(album.artists.joined(separator: ", "))")
    }

    private func play() {
        let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
        Task { await switcher.play(context: album.uri, with: playback, thenCollapse: collapse) }
    }
}
