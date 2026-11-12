import OrbitCore
import OrbitEngine
import SwiftUI

// The mini library: denser than the picker, with playlists to browse into, Liked Songs, the queue and Spotify
// search. The now-playing strip above keeps the way back to the player in view.
struct LibraryView: View {
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    var body: some View {
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
                        selection: Binding(
                            get: { navigator.libraryTab },
                            set: { tab in
                                // Choosing Search by hand means the user is about to type.
                                navigator.wantsSearchFocus = tab == .search
                                navigator.libraryTab = tab
                            }
                        )
                    )
                    .padding(.horizontal, OrbitTokens.Spacing.xl)
                    .padding(.top, OrbitTokens.Spacing.m)
                    ZStack(alignment: .top) {
                        let tab = navigator.libraryTab
                        content(for: tab)
                            .transformPreference(ListFitKey.self) { fits in
                                for index in fits.indices { fits[index].libraryTab = tab }
                            }
                            .id(tab)
                            .transition(.opacity.animation(theme.animation(OrbitTokens.Motion.screenFadeOut)))
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func content(for tab: LibraryTab) -> some View {
        switch tab {
        case .playlists: LibraryPlaylistsTab()
        case .liked: LikedSongsTab()
        case .queue: QueueTab()
        case .search: SearchTab()
        }
    }
}

// Lighter than SegmentedControl so a second row of navigation inside the library reads as a filter, not as a
// competing set of sections. Chips size to their labels and never truncate; if a narrower surface ever cannot
// hold them all, the Search glyph goes first.
struct ChipTabs<Value: Hashable>: View {
    let tabs: [Segment<Value>]
    @Binding var selection: Value

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips(showsSearchIcon: true)
            chips(showsSearchIcon: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library sections")
    }

    private func chips(showsSearchIcon: Bool) -> some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            ForEach(tabs) { tab in
                Chip(
                    tab: tab,
                    isSelected: tab.value == selection,
                    showsIcon: showsSearchIcon && tab.symbol == "magnifyingglass"
                ) { selection = tab.value }
            }
        }
        .fixedSize()
    }
}

private struct Chip<Value: Hashable>: View {
    let tab: Segment<Value>
    let isSelected: Bool
    let showsIcon: Bool
    let action: () -> Void

    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(theme.animation(OrbitTokens.Motion.navigate), action)
        } label: {
            HStack(spacing: OrbitTokens.Spacing.xs) {
                if showsIcon {
                    Image(systemName: tab.symbol).imageScale(.small)
                }
                Text(tab.title)
            }
            .font(OrbitTokens.Typography.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs)
            .frame(height: OrbitTokens.Size.chipHeight)
            .background {
                Capsule().fill(fill)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var fill: Color {
        if isSelected { return theme.accent.opacity(theme.isHighContrast ? 0.32 : 0.2) }
        return isHovered ? OrbitPalette.hoverFill(contrast: theme.contrast) : OrbitPalette.quietFill(contrast: theme.contrast)
    }
}

private struct LibraryPlaylistsTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var filter = ""
    @State private var selection = KeyboardSelection()

    private var shown: [Playlist] {
        let liked = LikedSongs.playlist(for: account.profile, count: library.savedTracks.value?.count)
        let all = [liked].compactMap { $0 } + (library.playlists.value ?? [])
        let query = filter.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : PickerContent.matches(for: query, in: all)
    }

    var body: some View {
        let shown = shown
        let keys = shown.map(\.id)
        let target = selection.target(in: keys, fallsBackToFirst: !filter.isEmpty && panel.isKeyWindow)
        VStack(spacing: 0) {
            SearchField(
                prompt: "Filter your playlists",
                text: $filter,
                focusesWhenKey: true,
                onSubmit: { play(target, in: shown) },
                onMove: { selection.move($0, in: keys) }
            )
            .padding(.horizontal, OrbitTokens.Spacing.xl)
            .padding(.vertical, OrbitTokens.Spacing.m)
            PanelScroll(reveal: selection.key) {
                switch library.playlists {
                case .idle, .loading:
                    SkeletonRows(count: 6)
                        .padding(.horizontal, OrbitTokens.Spacing.m)
                case .failed(let error):
                    StatusMessage(error: error) { Task { await library.loadPlaylists(force: true) } }
                        .listState()
                case .loaded(let playlists):
                    if shown.isEmpty {
                        StatusMessage(symbol: "magnifyingglass", title: "No playlists match “\(filter)”")
                            .listState()
                    } else {
                        LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                            ForEach(shown) { playlist in
                                PlaylistRow(playlist: playlist, behavior: .browse)
                                    .keyboardSelected(playlist.id == target)
                                    .id(playlist.id)
                            }
                            if playlists.isEmpty, filter.isEmpty {
                                StatusMessage(
                                    symbol: "music.note.list",
                                    title: "No playlists yet",
                                    message: "Playlists you create or follow in Spotify show up here."
                                )
                                .padding(.vertical, OrbitTokens.Spacing.xl)
                            }
                        }
                        .padding(.horizontal, OrbitTokens.Spacing.m)
                        .padding(.bottom, OrbitTokens.Spacing.m)
                    }
                }
            }
        }
        .onChange(of: keys) { _, keys in selection.reconcile(with: keys) }
        .onChange(of: filter) { selection.clear() }
        .task {
            if case .idle = library.playlists { await library.loadPlaylists() }
            // Liked Songs shows its count here as in the picker.
            if case .idle = library.savedTracks { await library.loadSavedTracks() }
        }
    }

    private func play(_ key: String?, in playlists: [Playlist]) {
        guard let key, let playlist = playlists.first(where: { $0.id == key }) else { return }
        Task { await switcher.play(playlist, with: playback, thenCollapse: panel.collapseAfterAction(preferences)) }
    }
}

private struct LikedSongsTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @State private var selection = KeyboardSelection()

    var body: some View {
        let context = LikedSongs.playlist(for: account.profile, count: nil)?.uri
        let tracks = library.savedTracks.value ?? []
        let keys = tracks.indices.map { "liked:\($0)" }
        PanelScroll(reveal: selection.key) {
            switch library.savedTracks {
            case .idle, .loading:
                SkeletonRows(count: 6)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.top, OrbitTokens.Spacing.m)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.loadSavedTracks(force: true) } }
                    .listState()
            case .loaded(let tracks) where tracks.isEmpty:
                StatusMessage(symbol: "heart", title: "No liked songs yet", message: "Tap the heart in the player to save a song.")
                    .listState()
            case .loaded(let tracks):
                LazyVStack(spacing: 0) {
                    SectionHeader(title: "Liked Songs", trailing: Formatting.songCount(tracks.count))
                    ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                        TrackRow(track: track, showsArtwork: true, context: context, isKeyboardSelected: selection.key == keys[index])
                            .id(keys[index])
                    }
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.bottom, OrbitTokens.Spacing.m)
            }
        }
        .keyboardList(selection: $selection, keys: keys) { key in
            guard let index = keys.firstIndex(of: key), tracks[index].isPlayable else { return }
            Task { await switcher.play(track: tracks[index], in: context, with: playback, thenCollapse: panel.collapseAfterAction(preferences)) }
        }
        .task {
            if case .idle = library.savedTracks { await library.loadSavedTracks() }
        }
    }
}

private struct QueueTab: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        PanelScroll {
            switch library.queue {
            case .idle, .loading:
                SkeletonRows(count: 6)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.top, OrbitTokens.Spacing.m)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.loadQueue(force: true) } }
                    .listState()
            case .loaded(let queue):
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
                        .padding(.vertical, OrbitTokens.Spacing.xl)
                    }
                    ForEach(Array(queue.upcoming.enumerated()), id: \.offset) { _, track in
                        TrackRow(track: track, showsArtwork: true, isInteractive: false)
                    }
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.bottom, OrbitTokens.Spacing.m)
            }
        }
        .panelKeyFocusTarget()
        // Reloaded on each track change, which is when the queue actually moves; there is no polling. The store
        // keeps the previous queue on screen while it reloads.
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
    @State private var selection = KeyboardSelection()

    var body: some View {
        @Bindable var navigator = navigator
        let results = library.searchResults.value ?? SearchResults()
        let keys = Self.keys(for: results)
        let target = selection.target(in: keys, fallsBackToFirst: panel.isKeyWindow)
        VStack(spacing: 0) {
            SearchField(
                prompt: "Search songs, albums, playlists",
                text: $navigator.searchQuery,
                focusOnAppear: navigator.wantsSearchFocus,
                focusesWhenKey: true,
                isBusy: library.isSearching,
                onSubmit: { activate(target, in: results) },
                onMove: { selection.move($0, in: keys) }
            )
            .padding(.horizontal, OrbitTokens.Spacing.xl)
            .padding(.vertical, OrbitTokens.Spacing.m)
            PanelScroll(reveal: selection.key) {
                list(results, target: target)
            }
        }
        .onAppear { navigator.wantsSearchFocus = false }
        .onChange(of: navigator.searchQuery, initial: true) { _, query in
            selection.clear()
            guard query != library.searchQuery || library.searchResults.value == nil else { return }
            library.updateSearch(query)
        }
        .onChange(of: keys) { _, keys in selection.reconcile(with: keys) }
    }

    @ViewBuilder
    private func list(_ results: SearchResults, target: String?) -> some View {
        let query = navigator.searchQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            StatusMessage(symbol: "magnifyingglass", title: "Search Spotify", message: "Find songs, albums and playlists to play right away.")
                .listState()
        } else {
            switch library.searchResults {
            case .idle, .loading:
                SkeletonRows(count: 5)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
            case .failed(let error):
                StatusMessage(error: error) { Task { await library.search(navigator.searchQuery) } }
                    .listState()
            case .loaded(let results) where results.isEmpty:
                StatusMessage(symbol: "magnifyingglass", title: "No results for “\(query)”", message: "Check the spelling or try fewer words.")
                    .listState()
            case .loaded:
                LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                    if !results.tracks.isEmpty {
                        SectionHeader(title: "Songs")
                        ForEach(Array(results.tracks.enumerated()), id: \.offset) { index, track in
                            TrackRow(track: track, showsArtwork: true, isKeyboardSelected: target == "track:\(index)")
                                .id("track:\(index)")
                        }
                    }
                    if !results.playlists.isEmpty {
                        SectionHeader(title: "Playlists")
                        ForEach(results.playlists) { playlist in
                            PlaylistRow(playlist: playlist, behavior: .browse)
                                .keyboardSelected(target == "playlist:\(playlist.id)")
                                .id("playlist:\(playlist.id)")
                        }
                    }
                    if !results.albums.isEmpty {
                        SectionHeader(title: "Albums")
                        ForEach(results.albums) { album in
                            AlbumRow(album: album)
                                .keyboardSelected(target == "album:\(album.id)")
                                .id("album:\(album.id)")
                        }
                    }
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.bottom, OrbitTokens.Spacing.m)
                // A newer query is on its way; the previous results stay readable but step back.
                .opacity(library.isSearching ? 0.6 : 1)
                .animation(theme.animation(OrbitTokens.Motion.hover), value: library.isSearching)
            }
        }
    }

    private static func keys(for results: SearchResults) -> [String] {
        results.tracks.indices.map { "track:\($0)" }
            + results.playlists.map { "playlist:\($0.id)" }
            + results.albums.map { "album:\($0.id)" }
    }

    private func activate(_ key: String?, in results: SearchResults) {
        guard let key else { return }
        let collapse = panel.collapseAfterAction(preferences)
        if key.hasPrefix("track:"), let index = Int(key.dropFirst("track:".count)), results.tracks.indices.contains(index) {
            let track = results.tracks[index]
            guard track.isPlayable else { return }
            Task { await switcher.play(track: track, in: nil, with: playback, thenCollapse: collapse) }
        } else if let playlist = results.playlists.first(where: { key == "playlist:\($0.id)" }) {
            Task { await switcher.play(playlist, with: playback, thenCollapse: collapse) }
        } else if let album = results.albums.first(where: { key == "album:\($0.id)" }) {
            Task { await switcher.play(context: album.uri, with: playback, thenCollapse: collapse) }
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
        let artists = album.artists.joined(separator: ", ")
        Button(action: play) {
            HStack(spacing: OrbitTokens.Spacing.l) {
                ArtworkView(url: album.artworkURL, size: OrbitTokens.Size.rowArtwork, placeholderSymbol: "square.stack")
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name)
                        .font(OrbitTokens.Typography.rowTitle)
                        .lineLimit(1)
                    Text(failure.map { "Couldn't play · \($0.message)" } ?? "Album · \(artists)")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(artists: artists, isCurrent: isCurrent, isPending: isPending, failure: failure))
        .accessibilityHint("Plays this album")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            Button("Open in Spotify") { SpotifyApp.open(album.uri) }
        }
    }

    private func accessibilityLabel(artists: String, isCurrent: Bool, isPending: Bool, failure: OrbitError?) -> String {
        var parts = [album.name, "album by \(artists)"]
        if isPending { parts.append("starting") }
        if let failure { parts.append("couldn't play: \(failure.message)") }
        if isCurrent { parts.append(playback.snapshot.isPlaying ? "now playing" : "paused") }
        return parts.joined(separator: ", ")
    }

    private func play() {
        Task { await switcher.play(context: album.uri, with: playback, thenCollapse: panel.collapseAfterAction(preferences)) }
    }
}
