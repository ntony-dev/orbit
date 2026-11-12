import OrbitCore
import OrbitEngine
import SwiftUI

// Everything to pick from, in one list: pins, recents, Liked Songs and every playlist, each a click away from
// playing and a chevron away from its tracks. Typing filters the playlists at once and searches Spotify below
// them after a pause, so a query never spends a request per keystroke. The arrow keys move a selection, Return
// plays it (or the top match while typing) and Right Arrow opens it. The now-playing strip above keeps the way
// back to the player in view.
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var selection = KeyboardSelection()
    // A playlist just pinned from a context menu, scrolled into view in its new section.
    @State private var newPin: String?

    var body: some View {
        @Bindable var navigator = navigator
        VStack(spacing: 0) {
            PanelTopBar { NowPlayingStrip() } accessory: { NowPlayingStrip.PlayPause() }
            AccountGate {
                let content = content
                VStack(spacing: 0) {
                    SearchField(
                        prompt: "Search your library and Spotify",
                        text: $navigator.searchQuery,
                        answersSearchRequests: true,
                        focusesWhenKey: true,
                        isBusy: library.isSearching,
                        onSubmit: { activate(selection.target(in: content.keys, fallsBackToFirst: content.isFiltered), in: content) },
                        onMove: { selection.move($0, in: content.keys) },
                        hasSelection: selection.key != nil,
                        onOpen: { open(selection.key, in: content) }
                    )
                    .padding(.horizontal, OrbitTokens.Spacing.xl)
                    .padding(.top, OrbitTokens.Spacing.m)
                    .padding(.bottom, OrbitTokens.Spacing.xs)
                    list(content)
                }
                .onChange(of: content.keys) { _, keys in selection.reconcile(with: keys) }
                .onChange(of: library.pinnedPlaylists.map(\.id)) { old, new in
                    newPin = new.first { !old.contains($0) }.map { "pinned:\($0)" }
                }
            }
        }
        .onChange(of: navigator.searchQuery, initial: true) { _, query in
            selection.clear()
            guard query != library.searchQuery || library.searchResults.value == nil else { return }
            library.updateSearch(query)
        }
        .task(id: account.authState) {
            guard account.authState.isSignedIn else { return }
            if case .idle = library.playlists { await library.loadPlaylists() }
            // Liked Songs shows its count on its row; its tracks load only when it is opened.
            if library.likedSongsCount == nil { await library.loadLikedSongsCount() }
        }
    }

    private var content: LibraryContent {
        LibraryContent(
            pinned: library.pinnedPlaylists,
            recents: library.recentPlaylists,
            liked: LikedSongs.playlist(for: account.profile, count: library.likedSongsCount),
            library: library.playlists.value ?? [],
            query: navigator.searchQuery,
            results: library.searchResults.value
        )
    }

    private func list(_ content: LibraryContent) -> some View {
        // While typing, the top match is what Return plays, so it carries the selection until the arrows move it.
        let target = selection.target(in: content.keys, fallsBackToFirst: content.isFiltered && panel.isKeyWindow)
        return PanelScroll(reveal: selection.key ?? newPin, revealAnchor: selection.key == nil ? .center : nil) {
            if content.isFiltered {
                LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                    playlistSections(content, target: target)
                    spotifySection(content, target: target)
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.bottom, OrbitTokens.Spacing.m)
            } else {
                switch library.playlists {
                case .idle, .loading:
                    SkeletonRows(count: 6)
                        .padding(.horizontal, OrbitTokens.Spacing.m)
                        .padding(.top, OrbitTokens.Spacing.s)
                case .failed(let error):
                    StatusMessage(error: error) { Task { await library.loadPlaylists(force: true) } }
                        .listState()
                case .loaded(let playlists):
                    LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                        playlistSections(content, target: target)
                        if playlists.isEmpty {
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

    @ViewBuilder
    private func playlistSections(_ content: LibraryContent, target: String?) -> some View {
        ForEach(content.sections) { section in
            SectionHeader(title: section.title)
            ForEach(section.entries) { entry in
                row(entry, inPinned: section.id == "pinned", isSelected: entry.id == target)
                    .id(entry.id)
            }
        }
    }

    // Spotify's results below the user's own matches. Until the first results arrive the section holds their
    // place; a newer query on its way leaves the previous results readable but stepped back.
    @ViewBuilder
    private func spotifySection(_ content: LibraryContent, target: String?) -> some View {
        switch library.searchResults {
        case .loaded(let results) where results.isEmpty || content.spotify.isEmpty:
            if content.sections.isEmpty {
                StatusMessage(
                    symbol: "magnifyingglass",
                    title: "Nothing matches “\(content.query)”",
                    message: "Check the spelling or try fewer words."
                )
                .listState()
            } else {
                SectionHeader(title: "Search Spotify")
                Text("No results on Spotify")
                    .font(OrbitTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OrbitTokens.Spacing.m)
                    .padding(.vertical, OrbitTokens.Spacing.s)
            }
        case .loaded:
            SectionHeader(title: "Search Spotify")
            ForEach(content.spotify) { group in
                SectionHeader(title: group.title, isSubheading: true)
                ForEach(group.entries) { entry in
                    row(entry, inPinned: false, isSelected: entry.id == target)
                        .id(entry.id)
                }
            }
            .opacity(library.isSearching ? 0.6 : 1)
            .animation(theme.animation(OrbitTokens.Motion.hover), value: library.isSearching)
        case .failed(let error):
            SectionHeader(title: "Search Spotify")
            StatusMessage(error: error) { Task { await library.search(navigator.searchQuery) } }
                .padding(.vertical, OrbitTokens.Spacing.l)
        case .idle, .loading:
            SectionHeader(title: "Search Spotify")
            SkeletonRows(count: 3)
        }
    }

    @ViewBuilder
    private func row(_ entry: LibraryContent.Entry, inPinned: Bool, isSelected: Bool) -> some View {
        switch entry.item {
        case .playlist(let playlist, let isRecent):
            let row = PlaylistRow(playlist: playlist, isRecent: isRecent)
                .keyboardSelected(isSelected)
            if inPinned {
                row
                    .draggable(playlist.id)
                    .dropDestination(for: String.self) { ids, _ in
                        movePinned(ids.first, before: playlist)
                    }
            } else {
                row
            }
        case .track(let track):
            TrackRow(track: track, showsArtwork: true, isKeyboardSelected: isSelected)
        case .album(let album):
            AlbumRow(album: album)
                .keyboardSelected(isSelected)
        }
    }

    private func activate(_ key: String?, in content: LibraryContent) {
        guard let key, let entry = content.entry(for: key) else { return }
        let collapse = panel.collapseAfterAction(preferences)
        switch entry.item {
        case .playlist(let playlist, _):
            Task { await switcher.play(playlist, with: playback, thenCollapse: collapse) }
        case .track(let track):
            guard track.isPlayable else { return }
            Task { await switcher.play(track: track, in: nil, with: playback, thenCollapse: collapse) }
        case .album(let album):
            Task { await switcher.play(context: album.uri, with: playback, thenCollapse: collapse) }
        }
    }

    private func open(_ key: String?, in content: LibraryContent) {
        guard let key, let playlist = content.entry(for: key)?.item.opensTracks else { return }
        withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.push(.playlist(playlist)) }
    }

    private func movePinned(_ id: String?, before target: Playlist) {
        let pinned = library.pinnedPlaylists
        guard let id, let source = pinned.firstIndex(where: { $0.id == id }),
              let destination = pinned.firstIndex(where: { $0.id == target.id }), source != destination
        else { return }
        withAnimation(theme.animation(OrbitTokens.Motion.content)) {
            library.movePinned(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        }
    }
}

private struct AlbumRow: View {
    let album: Album

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences

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
