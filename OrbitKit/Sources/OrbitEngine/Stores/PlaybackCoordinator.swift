import Foundation
import Observation
import OrbitCore

public enum PlaybackIntent: Hashable, Sendable {
    case playPause, next, previous, seek, volume, shuffle, repeatMode, toggleSaved
    case playContext(SpotifyURI)
    case playTrack(SpotifyURI)
    case transfer(deviceID: String)
}

// Single source of truth for playback state across every UI mode. This first pass forwards intents straight to
// the services with a naive optimistic update; reconciliation and smarter routing belong to the engine workstream.
@MainActor
@Observable
public final class PlaybackCoordinator {
    public private(set) var snapshot: PlaybackSnapshot = .idle
    // Intents sent but not yet confirmed, so the UI can show progress on exactly the control that was used.
    public private(set) var pendingIntents: Set<PlaybackIntent> = []
    public private(set) var isCurrentTrackSaved: Bool?
    public private(set) var lastError: OrbitError?

    @ObservationIgnored private let localPlayer: any LocalPlayer
    @ObservationIgnored private let api: any SpotifyAPI
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored var contextStarted: ((Playlist) -> Void)?

    public init(localPlayer: any LocalPlayer, api: any SpotifyAPI) {
        self.localPlayer = localPlayer
        self.api = api
    }

    public func start() {
        guard eventsTask == nil else { return }
        let events = localPlayer.events()
        eventsTask = Task { [weak self] in
            await self?.refresh()
            for await _ in events {
                await self?.refresh()
            }
        }
    }

    public func stop() {
        eventsTask?.cancel()
        eventsTask = nil
    }

    public func dismissError() {
        lastError = nil
    }

    public func refresh() async {
        let previousTrack = snapshot.track?.uri
        if let remote = try? await api.playbackState() {
            snapshot = remote
        } else if await localPlayer.isRunning() {
            do {
                snapshot = Self.snapshot(from: try await localPlayer.state(), merging: snapshot)
            } catch {
                lastError = error
            }
        } else {
            snapshot = .idle
        }
        if snapshot.track?.uri != previousTrack {
            await refreshSavedState()
        }
    }

    public func togglePlayPause() async {
        await perform(.playPause, optimistic: { $0.isPlaying.toggle() }) { () async throws(OrbitError) in
            try await localPlayer.playPause()
        }
    }

    public func next() async {
        await perform(.next) { () async throws(OrbitError) in try await localPlayer.nextTrack() }
    }

    public func previous() async {
        await perform(.previous) { () async throws(OrbitError) in try await localPlayer.previousTrack() }
    }

    public func seek(to position: TimeInterval) async {
        await perform(.seek, optimistic: { $0.position = position; $0.sampledAt = .now }) { () async throws(OrbitError) in
            try await localPlayer.setPosition(position)
        }
    }

    public func setVolume(_ percent: Int) async {
        let clamped = min(100, max(0, percent))
        await perform(.volume, optimistic: { $0.volume = clamped }) { () async throws(OrbitError) in
            try await localPlayer.setVolume(clamped)
        }
    }

    public func toggleShuffle() async {
        let enabled = !snapshot.shuffle
        await perform(.shuffle, optimistic: { $0.shuffle = enabled }) { () async throws(OrbitError) in
            try await localPlayer.setShuffling(enabled)
        }
    }

    public func setRepeat(_ mode: RepeatMode) async {
        await perform(.repeatMode, optimistic: { $0.repeatMode = mode }) { () async throws(OrbitError) in
            try await api.setRepeat(mode, deviceID: nil)
        }
    }

    public func cycleRepeat() async {
        await setRepeat(snapshot.repeatMode.next)
    }

    public func play(playlist: Playlist) async {
        await play(context: playlist.uri)
        if lastError == nil { contextStarted?(playlist) }
    }

    public func play(context uri: SpotifyURI) async {
        await perform(.playContext(uri)) { () async throws(OrbitError) in
            try await api.play(.context(uri), deviceID: nil)
        }
    }

    public func play(track: Track, in context: SpotifyURI? = nil) async {
        await perform(.playTrack(track.uri)) { () async throws(OrbitError) in
            try await localPlayer.play(track: track.uri, inContext: context)
        }
    }

    public func transfer(to device: PlaybackDevice) async {
        await perform(.transfer(deviceID: device.id)) { () async throws(OrbitError) in
            try await api.transferPlayback(to: device.id, play: snapshot.isPlaying)
        }
    }

    public func toggleSaved() async {
        guard let uri = snapshot.track?.uri, let saved = isCurrentTrackSaved else { return }
        isCurrentTrackSaved = !saved
        pendingIntents.insert(.toggleSaved)
        defer { pendingIntents.remove(.toggleSaved) }
        do {
            if saved {
                try await api.removeFromLibrary([uri])
            } else {
                try await api.saveToLibrary([uri])
            }
        } catch {
            isCurrentTrackSaved = saved
            lastError = error
        }
    }

    private func perform(
        _ intent: PlaybackIntent,
        optimistic update: (inout PlaybackSnapshot) -> Void = { _ in },
        _ operation: () async throws(OrbitError) -> Void
    ) async {
        let previous = snapshot
        update(&snapshot)
        pendingIntents.insert(intent)
        defer { pendingIntents.remove(intent) }
        do {
            try await operation()
            lastError = nil
        } catch {
            snapshot = previous
            lastError = error
            return
        }
        await refresh()
    }

    private func refreshSavedState() async {
        guard let uri = snapshot.track?.uri else {
            isCurrentTrackSaved = nil
            return
        }
        isCurrentTrackSaved = (try? await api.libraryContains([uri]))?.contains(uri)
    }

    private static func snapshot(from local: LocalPlayerState, merging previous: PlaybackSnapshot) -> PlaybackSnapshot {
        PlaybackSnapshot(
            track: local.track,
            isPlaying: local.status == .playing,
            position: local.position ?? 0,
            sampledAt: .now,
            shuffle: local.isShuffling ?? previous.shuffle,
            repeatMode: local.isRepeating.map { $0 ? .context : .off } ?? previous.repeatMode,
            context: previous.context,
            device: previous.device,
            volume: local.volume ?? previous.volume,
            availableActions: [.pause, .resume, .seek, .skipNext, .skipPrevious, .toggleShuffle, .toggleRepeatContext, .setVolume]
        )
    }
}
