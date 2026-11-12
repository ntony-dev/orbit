import OrbitCore
import OrbitEngine
import SwiftUI

// One-click playlist switching: pinned first, then recents, then the whole library with Liked Songs on top.
// Typing filters at once (the field takes focus whenever the open panel is key), the arrow keys move a selection
// and Return plays it, or the top match when nothing is selected.
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
    @State private var selection = KeyboardSelection()
    // A playlist just pinned from a context menu, scrolled into view in its new section.
    @State private var newPin: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelTopBar { NowPlayingStrip() }
            AccountGate {
                let content = content
                VStack(spacing: 0) {
                    SearchField(
                        prompt: "Filter playlists",
                        text: $filter,
                        focusesWhenKey: true,
                        onSubmit: { playSelection(in: content) },
                        onMove: { selection.move($0, in: content.keys) }
                    )
                    .padding(.horizontal, OrbitTokens.Spacing.xl)
                    .padding(.top, OrbitTokens.Spacing.m)
                    .padding(.bottom, OrbitTokens.Spacing.xs)
                    list(content)
                }
                .onChange(of: content.keys) { _, keys in selection.reconcile(with: keys) }
                .onChange(of: filter) { selection.clear() }
                .onChange(of: library.pinnedPlaylists.map(\.id)) { old, new in
                    newPin = new.first { !old.contains($0) }.map { "pinned:\($0)" }
                }
            }
        }
        .task(id: account.authState) {
            guard account.authState.isSignedIn else { return }
            if case .idle = library.playlists { await library.loadPlaylists() }
            if case .idle = library.savedTracks { await library.loadSavedTracks() }
        }
    }

    private var content: PickerContent {
        PickerContent(
            pinned: library.pinnedPlaylists,
            recents: library.recentPlaylists,
            liked: LikedSongs.playlist(for: account.profile, count: library.savedTracks.value?.count),
            library: library.playlists.value ?? [],
            filter: filter
        )
    }

    @ViewBuilder
    private func list(_ content: PickerContent) -> some View {
        PanelScroll(reveal: selection.key ?? newPin, revealAnchor: selection.key == nil ? .center : nil) {
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
                    rows(content, libraryIsEmpty: playlists.isEmpty)
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.bottom, OrbitTokens.Spacing.m)
            }
        }
    }

    @ViewBuilder
    private func rows(_ content: PickerContent, libraryIsEmpty: Bool) -> some View {
        // While typing, the filter's top match is what Return plays, so it carries the selection until the arrows
        // move it.
        let target = selection.target(in: content.keys, fallsBackToFirst: content.isFiltered && panel.isKeyWindow)
        ForEach(content.sections) { section in
            if let title = section.title {
                SectionHeader(title: title, trailing: section.trailing)
            }
            ForEach(section.entries) { entry in
                row(entry, in: section, isSelected: entry.id == target)
                    .id(entry.id)
            }
        }
        if content.isFiltered, content.keys.isEmpty {
            StatusMessage(
                symbol: "magnifyingglass",
                title: "No playlists match “\(filter.trimmingCharacters(in: .whitespaces))”",
                message: "Search all of Spotify instead.",
                actions: [StateAction(title: "Search Spotify", symbol: "magnifyingglass", isProminent: false) {
                    navigator.searchQuery = filter
                    navigator.wantsSearchFocus = true
                    withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.showLibrary(.search) }
                }]
            )
            .listState()
        } else if !content.isFiltered, libraryIsEmpty {
            StatusMessage(
                symbol: "music.note.list",
                title: "No playlists yet",
                message: "Playlists you create or follow in Spotify show up here."
            )
            .padding(.vertical, OrbitTokens.Spacing.xl)
        }
    }

    @ViewBuilder
    private func row(_ entry: PickerContent.Entry, in section: PickerContent.Section, isSelected: Bool) -> some View {
        let row = PlaylistRow(playlist: entry.playlist, isRecent: entry.isRecent)
            .keyboardSelected(isSelected)
        if section.id == "pinned" {
            row
                .draggable(entry.playlist.id)
                .dropDestination(for: String.self) { ids, _ in
                    movePinned(ids.first, before: entry.playlist)
                }
        } else {
            row
        }
    }

    private func playSelection(in content: PickerContent) {
        guard let key = selection.target(in: content.keys, fallsBackToFirst: content.isFiltered),
              let entry = content.entry(for: key)
        else { return }
        let collapse: (() -> Void)? = preferences.collapsesAfterAction ? { [panel] in panel.collapse() } : nil
        Task { await switcher.play(entry.playlist, with: playback, thenCollapse: collapse) }
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
