import OrbitCore
import OrbitEngine
import SwiftUI

// One-click playlist switching: pinned first, then recents, then the whole library with Liked Songs on top.
// Typing filters locally; Return plays the first match.
struct QuickPickerView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AccountStore.self) private var account
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences
    @Environment(\.orbitTheme) private var theme
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            PanelTopBar { NowPlayingStrip() }
            AccountGate {
                VStack(spacing: 0) {
                    SearchField(prompt: "Filter playlists", text: $filter, onSubmit: playFirstMatch) {
                        withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { _ = navigator.back() }
                    }
                    .padding(.horizontal, OrbitTokens.Spacing.xl)
                    .padding(.top, OrbitTokens.Spacing.m)
                    .padding(.bottom, OrbitTokens.Spacing.xs)
                    content
                }
            }
        }
        .task(id: account.authState) {
            guard account.authState.isSignedIn else { return }
            if case .idle = library.playlists { await library.loadPlaylists() }
            if case .idle = library.savedTracks { await library.loadSavedTracks() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.playlists {
        case .idle, .loading:
            SkeletonRows(count: 7)
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.top, OrbitTokens.Spacing.m)
                .frame(maxHeight: .infinity, alignment: .top)
        case .failed(let error):
            StatusMessage(error: error) { Task { await library.loadPlaylists() } }
                .frame(maxHeight: .infinity)
        case .loaded(let playlists):
            ScrollView {
                LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                    if filter.isEmpty {
                        sections(playlists)
                    } else {
                        matches(playlists)
                    }
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.bottom, OrbitTokens.Spacing.m)
            }
            .scrollIndicators(.automatic)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
    }

    private var likedSongs: Playlist? {
        LikedSongs.playlist(for: account.profile, count: library.savedTracks.value?.count)
    }

    @ViewBuilder
    private func sections(_ playlists: [Playlist]) -> some View {
        let pinned = library.pinnedPlaylists
        let recents = library.recentPlaylists.filter { !library.isPinned($0) }
        if !pinned.isEmpty {
            SectionHeader(title: "Pinned")
            ForEach(pinned) { playlist in
                PlaylistRow(playlist: playlist)
                    .draggable(playlist.id)
                    .dropDestination(for: String.self) { ids, _ in
                        movePinned(ids.first, before: playlist)
                    }
            }
        }
        if !recents.isEmpty {
            SectionHeader(title: "Recent")
            ForEach(recents.prefix(4)) { playlist in
                PlaylistRow(playlist: playlist, isRecent: true)
            }
        }
        SectionHeader(title: "Your Library", trailing: playlists.isEmpty ? nil : "\(playlists.count)")
        if let likedSongs {
            PlaylistRow(playlist: likedSongs)
        }
        ForEach(playlists) { playlist in
            PlaylistRow(playlist: playlist)
        }
        if playlists.isEmpty {
            StatusMessage(
                symbol: "music.note.list",
                title: "No playlists yet",
                message: "Playlists you create or follow in Spotify show up here."
            )
            .padding(.vertical, OrbitTokens.Spacing.xxl)
        }
    }

    @ViewBuilder
    private func matches(_ playlists: [Playlist]) -> some View {
        let found = filtered(playlists)
        if found.isEmpty {
            StatusMessage(
                symbol: "magnifyingglass",
                title: "No playlists match “\(filter)”",
                message: "Search all of Spotify instead.",
                actions: [StateAction(title: "Search Spotify", isProminent: false) {
                    navigator.searchQuery = filter
                    withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.showLibrary(.search) }
                }]
            )
            .padding(.vertical, OrbitTokens.Spacing.xxl)
        } else {
            ForEach(found) { playlist in
                PlaylistRow(playlist: playlist)
            }
        }
    }

    private func filtered(_ playlists: [Playlist]) -> [Playlist] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        return ([likedSongs].compactMap { $0 } + playlists).filter { $0.name.localizedStandardContains(query) }
    }

    private func playFirstMatch() {
        guard let first = filtered(library.playlists.value ?? []).first else { return }
        let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
        Task { await switcher.play(first, with: playback, thenCollapse: collapse) }
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
