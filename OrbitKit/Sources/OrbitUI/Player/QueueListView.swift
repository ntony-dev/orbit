import OrbitCore
import OrbitEngine
import SwiftUI

// What plays next, revealed in place under the player's volume row by the queue button, like the device list:
// the player already shows the current song, so only the songs after it are listed. Spotify cannot jump to a
// queued song, so the rows are not buttons; right-clicking one still opens it in Spotify. The list reports its
// height so the surface grows by exactly that much.
struct QueueListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(PanelNavigator.self) private var navigator

    var body: some View {
        content
            .padding(.top, OrbitTokens.Spacing.s)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigator.recordDrawerHeight($0, for: .queue) }
            // Reloaded on each track change, which is when the queue actually moves; there is no polling. The
            // store keeps the previous queue on screen while it reloads.
            .task(id: playback.snapshot.track?.id) {
                guard account.authState.isSignedIn else { return }
                await library.loadQueue()
            }
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
                        ForEach(Array(queue.upcoming.enumerated()), id: \.offset) { _, track in
                            TrackRow(track: track, showsArtwork: true, isInteractive: false)
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
}
