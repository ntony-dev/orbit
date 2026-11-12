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
    // How a play command ended, judged from what the coordinator returned rather than from its shared error, which
    // a newer command may already have set or cleared.
    enum Outcome: Equatable {
        case started
        case failed(OrbitError)
        // A newer switch replaced this one before Spotify confirmed it: neither a success nor a failure.
        case superseded

        init(started: Bool, error: OrbitError?) {
            if started {
                self = .started
            } else if let error {
                self = .failed(error)
            } else {
                self = .superseded
            }
        }
    }

    private(set) var failures: [SpotifyURI: OrbitError] = [:]
    private(set) var confirmed: SpotifyURI?

    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    func failure(for uri: SpotifyURI) -> OrbitError? {
        failures[uri]
    }

    func play(_ playlist: Playlist, with playback: PlaybackCoordinator, thenCollapse collapse: (() -> Void)?) async {
        begin(playlist.uri)
        let started = await playback.play(playlist: playlist)
        await settle(playlist.uri, Outcome(started: started, error: playback.lastError), collapse: collapse)
    }

    func play(track: Track, in context: SpotifyURI?, with playback: PlaybackCoordinator, thenCollapse collapse: (() -> Void)?) async {
        begin(track.uri)
        let started = await playback.play(track: track, in: context)
        await settle(track.uri, Outcome(started: started, error: playback.lastError), collapse: collapse)
    }

    func play(context uri: SpotifyURI, with playback: PlaybackCoordinator, thenCollapse collapse: (() -> Void)?) async {
        begin(uri)
        let started = await playback.play(context: uri)
        await settle(uri, Outcome(started: started, error: playback.lastError), collapse: collapse)
    }

    func dismissFailure(for uri: SpotifyURI) {
        failures[uri] = nil
    }

    private func begin(_ uri: SpotifyURI) {
        failures[uri] = nil
        confirmationTask?.cancel()
        confirmed = nil
    }

    func settle(_ uri: SpotifyURI, _ outcome: Outcome, collapse: (() -> Void)?) async {
        switch outcome {
        case .superseded:
            return
        case .failed(let error):
            failures[uri] = error
            return
        case .started:
            break
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

extension PanelState {
    // What a finished switch runs afterwards: a collapse when the user asked Orbit to get out of the way.
    func collapseAfterAction(_ preferences: Preferences) -> (() -> Void)? {
        preferences.collapsesAfterAction ? { [weak self] in self?.collapse() } : nil
    }
}
