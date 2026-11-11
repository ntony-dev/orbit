import Foundation
import Observation
import OrbitCore
import OrbitEngine

// Per-row outcome of a playlist switch. Pending comes from the coordinator's pendingIntents; this keeps what the
// coordinator forgets once a command finishes: which switch failed (so it never looks like a success) and which
// one just succeeded (so the row can confirm it before the panel collapses).
@MainActor
@Observable
final class PlaylistSwitcher {
    private(set) var failures: [SpotifyURI: OrbitError] = [:]
    private(set) var confirmed: SpotifyURI?

    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    func failure(for uri: SpotifyURI) -> OrbitError? {
        failures[uri]
    }

    func play(_ playlist: Playlist, with playback: PlaybackCoordinator, thenCollapse collapse: (() -> Void)?) async {
        failures[playlist.uri] = nil
        confirmationTask?.cancel()
        confirmed = nil
        await playback.play(playlist: playlist)
        await settle(playlist.uri, error: playback.lastError, collapse: collapse)
    }

    func play(track: Track, in context: SpotifyURI?, with playback: PlaybackCoordinator, thenCollapse collapse: (() -> Void)?) async {
        failures[track.uri] = nil
        await playback.play(track: track, in: context)
        await settle(track.uri, error: playback.lastError, collapse: collapse)
    }

    func play(context uri: SpotifyURI, with playback: PlaybackCoordinator, thenCollapse collapse: (() -> Void)?) async {
        failures[uri] = nil
        await playback.play(context: uri)
        await settle(uri, error: playback.lastError, collapse: collapse)
    }

    func dismissFailure(for uri: SpotifyURI) {
        failures[uri] = nil
    }

    private func settle(_ uri: SpotifyURI, error: OrbitError?, collapse: (() -> Void)?) async {
        if let error {
            failures[uri] = error
            return
        }
        confirmed = uri
        let task = Task { [weak self] in
            try? await Task.sleep(for: OrbitTokens.Motion.confirmationHold)
            guard !Task.isCancelled else { return }
            collapse?()
            try? await Task.sleep(for: OrbitTokens.Motion.confirmationHold)
            guard !Task.isCancelled else { return }
            if self?.confirmed == uri { self?.confirmed = nil }
        }
        confirmationTask = task
        await task.value
    }
}
