import OrbitCore
import OrbitEngine
import SwiftUI

// What plays next, revealed in place under the player's volume row by the queue button, like the device list:
// the player already shows the current song, so only the songs after it are listed. Clicking a song skips to it
// as Spotify's own queue does, dropping the songs before it; Spotify has no command for that, so the coordinator
// sends "next" once per song up to it. The list reports its height so the surface grows by exactly that much.
struct QueueListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PlaylistSwitcher.self) private var switcher
    @Environment(PanelState.self) private var panel
    @Environment(Preferences.self) private var preferences

    var body: some View {
        content
            .padding(.top, OrbitTokens.Spacing.s)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigator.recordDrawerHeight($0, for: .queue) }
            // Reloaded on each track change, which is when the queue actually moves; there is no polling. The
            // store keeps the previous queue on screen while it reloads. A skip to a queued song changes the
            // track once, at the end, and the coordinator's own reload then answers this one too.
            .task(id: playback.snapshot.track?.id) {
                guard account.authState.isSignedIn else { return }
                await library.loadQueue()
            }
            .task { await runDebugSkip() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Queue")
    }

    @ViewBuilder
    private var content: some View {
        switch account.authState {
        case .unknown:
            SkeletonRows(count: 2)
        case .signedOut:
            DrawerMessage(
                symbol: "person.crop.circle.badge.plus",
                title: "Connect Spotify to see your queue",
                action: StateAction(title: "Connect") { Task { await account.signIn() } }
            )
        case .authorizing:
            DrawerMessage(symbol: "safari", title: "Finish signing in in your browser")
        case .signedIn:
            queue
        }
    }

    @ViewBuilder
    private var queue: some View {
        switch library.queue {
        case .idle, .loading:
            SkeletonRows(count: 2)
        case .failed(let error):
            DrawerMessage(
                symbol: "exclamationmark.triangle",
                title: error.message,
                detail: error.recoveryHint,
                action: StateAction(title: "Try Again") { Task { await library.loadQueue(force: true) } }
            )
        case .loaded(let queue) where queue.upcoming.isEmpty:
            DrawerMessage(
                symbol: "text.line.first.and.arrowtriangle.forward",
                title: "Nothing queued",
                detail: "Right-click a song in your library and choose Add to Queue."
            )
        case .loaded(let queue):
            VStack(spacing: 0) {
                SectionHeader(title: "Up Next", trailing: Formatting.songCount(queue.upcoming.count))
                let rows = ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(queue.upcoming.enumerated()), id: \.offset) { index, track in
                            TrackRow(
                                track: track,
                                showsArtwork: true,
                                action: TrackRow.Action(title: "Skip to This Song", hint: "Skips to this song") {
                                    skip(to: index, in: queue.upcoming)
                                }
                            )
                        }
                    }
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                let visible = min(queue.upcoming.count, OrbitTokens.Size.queueVisibleRows)
                rows
                    .frame(height: CGFloat(visible) * OrbitTokens.Size.artworkTrackRowHeight)
                    .scrollDisabled(queue.upcoming.count <= OrbitTokens.Size.queueVisibleRows)
            }
        }
    }

    // The song at `index` is `index + 1` skips away: one for each song before it and one for itself.
    private func skip(to index: Int, in upcoming: [Track], collapses: Bool = true) {
        let track = upcoming[index]
        let collapse = collapses ? panel.collapseAfterAction(preferences) : nil
        Task {
            switcher.dismissFailure(for: track.uri)
            let result = await playback.skipAhead(by: index + 1, to: track.uri)
            await switcher.settle(track.uri, PlaylistSwitcher.Outcome(result), collapse: collapse)
        }
    }

    private func runDebugSkip() async {
        #if DEBUG
        guard let index = UIDebugOptions.current.skipQueueIndex else { return }
        for _ in 0..<50 where library.queue.value == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard let upcoming = library.queue.value?.upcoming, upcoming.indices.contains(index) else { return }
        skip(to: index, in: upcoming, collapses: false)
        #endif
    }
}

private extension PlaylistSwitcher.Outcome {
    init(_ result: SkipAheadResult) {
        switch result {
        case .landed: self = .started
        // The skip already running speaks for the row that was clicked first.
        case .ignored: self = .superseded
        case .failed(let error): self = .failed(error)
        }
    }
}
