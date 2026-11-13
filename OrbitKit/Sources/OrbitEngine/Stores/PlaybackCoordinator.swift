import Foundation
import Observation
import OrbitCore

public enum PlaybackIntent: Hashable, Sendable {
    case playPause, next, previous, seek, volume, shuffle, repeatMode, toggleSaved
    case playContext(SpotifyURI)
    case playTrack(SpotifyURI)
    case transfer(deviceID: String)
}

// How a skip to a queued song ended, judged by the operation itself rather than the shared `lastError`.
public enum SkipAheadResult: Hashable, Sendable {
    case landed
    // Another skip to a queued song was still running, so this one sent nothing.
    case ignored
    // `.playbackNotConfirmed` when every skip went through but Spotify was not seen on the song asked for, as
    // when the queue changed after it was shown.
    case failed(OrbitError)
}

public enum PlaybackRoute: String, Hashable, Sendable {
    // AppleScript to the Spotify app on this Mac.
    case local
    case webAPI
}

// How much of Orbit is on screen, which sets how often the Web API is asked for playback state.
public enum InterfaceVisibility: Hashable, Sendable {
    case hidden
    case collapsed
    case expanded
}

// Single source of truth for playback state across every UI mode.
//
// Authority: while the Spotify app on this Mac is the active device, its AppleScript state and distributed
// notification drive the snapshot and the Web API only adds context, device and artwork. When another device is
// playing, or the app is closed, the Web API snapshot is authoritative. Transport goes to the authoritative side
// first. Starting a playlist, album or track, and setting repeat, go to the Web API first, aimed at this Mac by
// device ID while it is the device in use, because the app's `play track` brings its window up and its repeat is
// only on or off. Either falls back to the other route when its own is unavailable.
//
// Races: commands run one at a time in issue order. Each optimistic change is an overlay on top of the last
// observed state; it stays until an observation agrees with it or its grace period ends, so a stale notification
// or a slow response can never undo a newer intent. Web API reads that began before a command finished are dropped.
@MainActor
@Observable
public final class PlaybackCoordinator {
    public struct Timing: Sendable {
        public var confirmationTimeout: Duration = .seconds(6)
        // How long an optimistic value outlives its command. The Web API reflects changes more slowly than the app.
        public var localOverlayGrace: Duration = .milliseconds(1500)
        public var overlayGrace: Duration = .seconds(3)
        public var webSettleDelay: Duration = .milliseconds(700)
        public var trackChangeTimeout: Duration = .milliseconds(1500)
        // How long Spotify's own notification of a track change gets before the state is read instead.
        public var notificationGrace: Duration = .milliseconds(300)
        public var defaultBackoff: TimeInterval = 30
        // Spotify's queue endpoint lists about twenty songs; nothing on screen can ask for more.
        public var skipAheadLimit = 30

        public init() {}
    }

    public private(set) var snapshot: PlaybackSnapshot = .idle
    // Intents sent but not yet confirmed, so the UI can show progress on exactly the control that was used.
    public var pendingIntents: Set<PlaybackIntent> { Set(pendingCounts.keys) }
    public var isCurrentTrackSaved: Bool? {
        guard let savedState, savedState.uri == snapshot.track?.uri else { return nil }
        return savedState.saved
    }
    public private(set) var lastError: OrbitError?
    // Which side `snapshot` comes from; nil when nothing is playing anywhere Orbit can see.
    public private(set) var authority: PlaybackRoute?
    // The user's synchronization setting, which scales the regular Web API sync interval.
    public var syncFrequency: SyncFrequency = .standard {
        // A shorter interval applies at once; a longer one from the next sync, which is already scheduled.
        didSet { if syncFrequency != oldValue { scheduleSync(after: nil) } }
    }
    // Set while Spotify rate limits Orbit or the quota is spent; local controls keep working meanwhile.
    public private(set) var webAPIPausedUntil: Date?
    // The last failure of background syncing, kept apart from `lastError` so polling never interrupts the user.
    public private(set) var syncError: OrbitError?

    @ObservationIgnored var contextStarted: ((Playlist) -> Void)?
    @ObservationIgnored var contextNotFound: ((SpotifyURI) -> Void)?
    @ObservationIgnored var contextName: ((SpotifyURI) -> String?)?
    // Known track URIs of a context, used to tell a confirmed switch from an unrelated track change.
    @ObservationIgnored var contextTracks: ((SpotifyURI) -> Set<SpotifyURI>?)?
    @ObservationIgnored var preferredDeviceID: (() -> String?)?
    @ObservationIgnored var automationDenied: (() -> Void)?
    // Runs once after a skip to a queued song moved playback, with the song now playing, so the queue is read
    // again once rather than for every song passed over.
    @ObservationIgnored var skippedAhead: (@MainActor (SpotifyURI?) async -> Void)?

    @ObservationIgnored private let localPlayer: any LocalPlayer
    @ObservationIgnored private let api: any SpotifyAPI
    @ObservationIgnored private let clock: EngineClock
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private let availability: LocalAvailabilityCheck

    @ObservationIgnored private var local: LocalObservation?
    @ObservationIgnored private var localRunning = false
    @ObservationIgnored private var localPermission = AutomationPermission.notDetermined
    @ObservationIgnored private var localDeviceName: String?
    @ObservationIgnored private var localDeviceID: String?
    @ObservationIgnored private var remote: RemoteObservation?
    @ObservationIgnored private var interfaceVisibility = InterfaceVisibility.collapsed
    // The context Orbit itself confirmed starting, ordered against Web API reads by `contextSequence`.
    @ObservationIgnored private var knownContext: (context: PlaybackContext, sequence: Int)?
    @ObservationIgnored private var contextSequence = 0
    @ObservationIgnored private var webSignedIn = true
    // This Mac's repeat mode, folded from observations in the order they arrived: AppleScript reads say only on or
    // off, so they settle that, and Web API reads of this Mac say which "on". Nil until either has been seen.
    @ObservationIgnored private var localRepeat: RepeatMode?
    // Counts observations so a Web API read can tell whether an AppleScript read landed while it was in flight.
    @ObservationIgnored private var observationCount = 0
    @ObservationIgnored private var lastLocalRepeatRead = 0

    private var pendingCounts: [PlaybackIntent: Int] = [:]
    @ObservationIgnored private var overlays: [Field: Overlay] = [:]
    // Numbers commands in issue order: overlays apply in this order and coalescing keeps the highest per intent.
    @ObservationIgnored private var lastCommandID = 0
    @ObservationIgnored private var latestIntent: [PlaybackIntent: Int] = [:]
    @ObservationIgnored private var commandTail: Task<Void, Never>?
    @ObservationIgnored private var commandEpoch = 0
    // Set while a skip is in flight, so a seek issued meanwhile lands on the new track rather than the old one.
    @ObservationIgnored private var skipInFlight: (from: SpotifyURI?, id: Int)?
    @ObservationIgnored private var skipAheadID: Int?
    @ObservationIgnored private var switchGeneration = 0
    @ObservationIgnored private var switchWaiterID: Int?
    @ObservationIgnored private var webPauseReason: OrbitError?

    @ObservationIgnored private var waiters: [Int: Waiter] = [:]
    @ObservationIgnored private var nextWaiterID = 0

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var remoteFetch: Task<Void, Never>?
    @ObservationIgnored private var scheduledSync: (due: Date, task: Task<Void, Never>)?
    @ObservationIgnored private var overlayExpiry: Task<Void, Never>?
    // The last saved state Orbit learned and the track it belongs to; it answers whenever that track is playing.
    private var savedState: (uri: SpotifyURI, saved: Bool)?
    // What Spotify answered for the current track, unaffected by toggles since: whether it belongs to Liked Songs
    // when that plays as a plain track list, without loading the whole collection.
    @ObservationIgnored private var likedMembership: (uri: SpotifyURI, saved: Bool)?

    public convenience init(localPlayer: any LocalPlayer, api: any SpotifyAPI, clock: EngineClock = .system, timing: Timing = Timing()) {
        self.init(localPlayer: localPlayer, api: api, clock: clock, timing: timing, availability: LocalAvailabilityCheck(localPlayer: localPlayer))
    }

    init(localPlayer: any LocalPlayer, api: any SpotifyAPI, clock: EngineClock, timing: Timing, availability: LocalAvailabilityCheck) {
        self.localPlayer = localPlayer
        self.api = api
        self.clock = clock
        self.timing = timing
        self.availability = availability
    }

    public func start() {
        guard tasks.isEmpty else { return }
        let events = localPlayer.events()
        tasks.append(Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        })
        tasks.append(Task { [weak self] in
            await self?.refresh()
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        scheduledSync?.task.cancel()
        scheduledSync = nil
        overlayExpiry?.cancel()
    }

    public func dismissError() {
        lastError = nil
    }

    // The shell reports what is on screen: the Web API is polled every few seconds while expanded and remote
    // playback is authoritative, slowly while only the pill shows, and never while Orbit is hidden.
    public func setInterfaceVisibility(_ visibility: InterfaceVisibility) {
        guard visibility != interfaceVisibility else { return }
        let wasHidden = interfaceVisibility == .hidden
        interfaceVisibility = visibility
        if visibility == .expanded || wasHidden {
            Task { await refreshLocalAvailability() }
            let stale = remote.map { clock.now().timeIntervalSince($0.at) > 2 } ?? true
            scheduleSync(after: stale ? .zero : nil)
        } else {
            scheduleSync(after: nil)
        }
    }

    // Called with the account's sign-in state, so a signed-out Orbit makes no Web API calls at all.
    func setWebAPIAvailable(_ available: Bool) {
        guard available != webSignedIn else { return }
        webSignedIn = available
        if !available {
            remote = nil
            localDeviceID = nil
            savedState = nil
            likedMembership = nil
            syncError = nil
            webAPIPausedUntil = nil
            webPauseReason = nil
        }
        recompute()
        scheduleSync(after: available ? .zero : nil)
    }

    func libraryChanged() {
        recompute()
    }

    public func refresh() async {
        await refreshLocal()
        await refreshRemote()
    }

    public func togglePlayPause() async {
        let playing = !snapshot.isPlaying
        let frozen = snapshot.position(at: clock.now())
        let track = snapshot.track?.uri
        let issued = clock.now()
        await run(
            .playPause,
            overlay: (.playing, { snapshot in
                snapshot.isPlaying = playing
                if snapshot.track?.uri == track {
                    snapshot.position = frozen
                    snapshot.sampledAt = issued
                }
            }, { $0.isPlaying == playing }),
            coalesces: true,
            local: { player in try await playing ? player.play() : player.pause() },
            web: { api, device in try await playing ? api.resume(deviceID: device) : api.pause(deviceID: device) }
        )
    }

    public func next() async {
        await changeTrack(.next, local: { try await $0.nextTrack() }, web: { try await $0.skipToNext(deviceID: $1) })
    }

    public func previous() async {
        await changeTrack(.previous, local: { try await $0.previousTrack() }, web: { try await $0.skipToPrevious(deviceID: $1) })
    }

    // Spotify cannot jump to a queued song, so reaching one is "next" once per song up to it, sent as one
    // operation: every skip takes the route the first one took, with no read-back, Web API read or saved-state
    // check between them, and the player keeps showing the song it was on, so the songs passed over never reach
    // the screen or load their artwork. One reconciliation and one queue reload follow the last skip. A second
    // call while one runs is ignored, because its count was taken from a queue that is about to change.
    @discardableResult
    public func skipAhead(by count: Int, to target: SpotifyURI) async -> SkipAheadResult {
        guard skipAheadID == nil else { return .ignored }
        let id = nextCommandID()
        skipAheadID = id
        let intent = PlaybackIntent.playTrack(target)
        addPending(intent)
        defer {
            skipAheadID = nil
            removePending(intent)
        }
        let held = snapshot
        overlays[.track] = Overlay(id: id, apply: { snapshot in
            snapshot.track = held.track
            snapshot.context = held.context
            snapshot.isPlaying = held.isPlaying
            snapshot.position = held.position
            snapshot.sampledAt = held.sampledAt
        }, isSatisfied: { _ in false })
        recompute()
        let skips = min(max(1, count), timing.skipAheadLimit)
        let local: LocalCommand = { try await $0.nextTrack() }
        let web: WebCommand = { try await $0.skipToNext(deviceID: $1) }
        let sent = await enqueue { [self] () async -> (route: PlaybackRoute?, failure: OrbitError?) in
            var route: PlaybackRoute?
            for _ in 0..<skips {
                let result = await deliver(local: route == .webAPI ? nil : local, web: route == .local ? nil : web)
                commandEpoch += 1
                switch result {
                case .success(let used): route = used
                case .failure(let error): return (route, error)
                }
            }
            return (route, nil)
        }
        var landed = false
        if let route = sent.route {
            landed = await reconcileSkips(over: route, reaching: sent.failure == nil ? target : nil)
        }
        if overlays[.track]?.id == id { overlays[.track] = nil }
        let failure = sent.failure ?? (landed ? nil : OrbitError.playbackNotConfirmed)
        lastError = failure
        recompute()
        // Nothing moved, so the queue on screen is still true.
        guard sent.route != nil else { return .failed(failure ?? .playbackNotConfirmed) }
        if interfaceVisibility != .hidden {
            Task { await refreshSavedState() }
            // AppleScript cannot say which context or device; one Web API read for the song landed on can.
            if sent.route == .local { scheduleSync(after: .seconds(1)) }
        }
        await skippedAhead?(snapshot.track?.uri)
        return failure.map { .failed($0) } ?? .landed
    }

    public func seek(to position: TimeInterval) async {
        let target = max(0, min(position, snapshot.track?.duration ?? position))
        let issued = clock.now()
        let now = clock.now
        await run(
            .seek,
            overlay: (.position, { snapshot in
                snapshot.position = target
                snapshot.sampledAt = issued
            }, { snapshot in
                let expected = target + (snapshot.isPlaying ? now().timeIntervalSince(issued) : 0)
                return abs(snapshot.position(at: now()) - expected) < 2
            }),
            coalesces: true,
            waitsForTrackChange: true,
            local: { try await $0.setPosition(target) },
            web: { try await $0.seek(to: target, deviceID: $1) }
        )
    }

    public func setVolume(_ percent: Int) async {
        let clamped = min(100, max(0, percent))
        await run(
            .volume,
            overlay: (.volume, { snapshot in
                snapshot.volume = clamped
                snapshot.device?.volumePercent = clamped
            }, { $0.volume == clamped }),
            coalesces: true,
            local: { try await $0.setVolume(clamped) },
            web: { try await $0.setVolume(clamped, deviceID: $1) }
        )
    }

    public func toggleShuffle() async {
        let enabled = !snapshot.shuffle
        await run(
            .shuffle,
            overlay: (.shuffle, { $0.shuffle = enabled }, { $0.shuffle == enabled }),
            coalesces: true,
            local: { try await $0.setShuffling(enabled) },
            web: { try await $0.setShuffle(enabled, deviceID: $1) }
        )
    }

    // The Web API sets the exact mode. AppleScript only knows on or off, so it is the fallback for those two alone,
    // and its "on" is sent only from off: what it does to repeat-one is not Orbit's to guess.
    func setRepeat(_ mode: RepeatMode) async {
        var local: LocalCommand?
        if mode != .track {
            local = { player in try await player.setRepeating(mode == .context) }
        }
        await run(
            .repeatMode,
            overlay: (.repeatMode, { $0.repeatMode = mode }, { $0.repeatMode == mode }),
            coalesces: true,
            preferring: .webAPI,
            local: local,
            web: { try await $0.setRepeat(mode, deviceID: $1) }
        )
    }

    public func cycleRepeat() async {
        var mode = snapshot.repeatMode.next
        if mode == .track, !snapshot.allows(.toggleRepeatTrack) { mode = .off }
        await setRepeat(mode)
    }

    // Returns once Spotify is seen playing the playlist, or with `lastError` set when it is not.
    @discardableResult
    public func play(playlist: Playlist) async -> Bool {
        let started = await play(context: playlist.uri, name: playlist.name)
        if started { contextStarted?(playlist) }
        return started
    }

    @discardableResult
    public func play(context uri: SpotifyURI) async -> Bool {
        await play(context: uri, name: nil)
    }

    private func play(context uri: SpotifyURI, name: String?) async -> Bool {
        let tracks = contextTracks?(uri)
        let started = await start(
            .playContext(uri),
            local: { try await $0.play(track: uri, inContext: nil) },
            // Liked Songs goes out as its collection context too: when Spotify refuses that, the Web client itself
            // falls back to playing the saved tracks as a list.
            web: { try await $0.play(.context(uri), deviceID: $1) },
            confirmed: { observation, before in
                if let context = observation.context {
                    return context == uri || (LikedSongs.isLikedSongs(context) && LikedSongs.isLikedSongs(uri))
                }
                // After that fallback, Web API state never names a context; the track is all there is to go on.
                guard observation.isLocal || LikedSongs.isLikedSongs(uri) else { return false }
                guard observation.isPlaying, let track = observation.track else { return false }
                if let tracks, !tracks.isEmpty { return tracks.contains(track) }
                return track != before || (observation.position ?? .infinity) < 3
            }
        ) { [weak self] in
            self?.adopt(context: uri, name: name)
        }
        if !started, lastError == .notFound { contextNotFound?(uri) }
        return started
    }

    @discardableResult
    public func play(track: Track, in context: SpotifyURI? = nil) async -> Bool {
        let target: PlayTarget = context.map { .context($0, offset: .track(track.uri)) } ?? .tracks([track.uri])
        return await start(
            .playTrack(track.uri),
            local: { try await $0.play(track: track.uri, inContext: context) },
            web: { try await $0.play(target, deviceID: $1) },
            confirmed: { observation, _ in observation.track == track.uri }
        ) { [weak self] in
            if let context { self?.adopt(context: context, name: nil) }
        }
    }

    public func transfer(to device: PlaybackDevice) async {
        let play = snapshot.isPlaying
        var active = device
        active.isActive = true
        await run(
            .transfer(deviceID: device.id),
            overlay: (.device, { $0.device = active }, { $0.device?.id == device.id }),
            local: nil,
            web: { api, _ in try await api.transferPlayback(to: device.id, play: play) }
        )
    }

    public func toggleSaved() async {
        guard let uri = snapshot.track?.uri, let saved = isCurrentTrackSaved else { return }
        guard webUsable else {
            lastError = webUnavailableError
            return
        }
        savedState = (uri, !saved)
        addPending(.toggleSaved)
        defer { removePending(.toggleSaved) }
        do {
            if saved {
                try await api.removeFromLibrary([uri])
            } else {
                try await api.saveToLibrary([uri])
            }
            noteWebSuccess()
        } catch {
            noteWebFailure(error)
            if savedState?.uri == uri { savedState = (uri, saved) }
            lastError = error
        }
    }

    // Plain-value rule for how often to sync from the Web API; nil means only on events.
    static func syncDelay(
        visibility: InterfaceVisibility,
        authority: PlaybackRoute?,
        untilTrackEnds: TimeInterval?,
        frequency: SyncFrequency = .standard
    ) -> Duration? {
        if frequency == .whileOpen, visibility == .collapsed { return nil }
        let standard: TimeInterval? = switch (visibility, authority) {
        case (.hidden, _): nil
        case (.expanded, .webAPI): 5
        case (.collapsed, .webAPI): 15
        case (.expanded, .local): 30
        case (.collapsed, .local): nil
        case (.expanded, nil): 10
        case (.collapsed, nil): 60
        }
        guard let standard else { return nil }
        let base = frequency == .reduced ? standard * 3 : standard
        guard authority == .webAPI, let remaining = untilTrackEnds else { return .seconds(base) }
        return .seconds(max(1, min(base, remaining + 1)))
    }
}

extension PlaybackCoordinator {
    private enum Field: Hashable {
        case playing, position, shuffle, repeatMode, volume, device
        // Holds the song on screen while a skip to a queued song passes over the ones before it.
        case track
    }

    private struct Overlay {
        let id: Int
        let apply: (inout PlaybackSnapshot) -> Void
        let isSatisfied: (PlaybackSnapshot) -> Bool
        // Nil while the command is in flight; afterwards the overlay holds only until this moment.
        var expiresAt: Date?
    }

    private struct LocalObservation {
        var state: LocalPlayerState
        var at: Date
    }

    private struct RemoteObservation {
        var snapshot: PlaybackSnapshot?
        var at: Date
        var sequence: Int
    }

    private struct ObservedState {
        var track: SpotifyURI?
        var context: SpotifyURI?
        var isPlaying: Bool
        var position: TimeInterval?
        var isLocal: Bool
    }

    private struct SentCommand: Sendable {
        var trackBefore: SpotifyURI?
        var result: Result<PlaybackRoute, OrbitError>
    }

    private struct Waiter {
        let matches: (ObservedState) -> Bool
        let continuation: CheckedContinuation<Bool, Never>
    }

    // Which route a command tries first when this Mac's app is the device in use. Transport prefers the app, which
    // answers in milliseconds; starting something new prefers the Web API, which plays without showing Spotify, and
    // so does repeat, which the Web API sets exactly.
    private enum RoutePreference {
        case local, webAPI
    }

    // Untyped so command closures stay one-liners; every service behind them throws OrbitError.
    private typealias LocalCommand = @Sendable (any LocalPlayer) async throws -> Void
    private typealias WebCommand = @Sendable (any SpotifyAPI, String?) async throws -> Void

    private var webUsable: Bool {
        guard webSignedIn else { return false }
        guard let until = webAPIPausedUntil else { return true }
        return clock.now() >= until
    }

    private var localCommandsUsable: Bool {
        localRunning && localPermission != .denied && localPermission != .requiresSpotifyRunning
    }

    private var webUnavailableError: OrbitError {
        guard webSignedIn else { return .notSignedIn }
        let remaining = webAPIPausedUntil.map { max(0, $0.timeIntervalSince(clock.now())) }
        if case .quotaExceeded = webPauseReason { return .quotaExceeded(retryAfter: remaining) }
        return .rateLimited(retryAfter: remaining)
    }

    // Errors that say the route itself is unusable, as opposed to the request being refused on its merits.
    private static func isRouteFailure(_ error: OrbitError) -> Bool {
        switch error {
        case .spotifyNotRunning, .spotifyNotInstalled, .automationDenied, .notSignedIn, .authExpired, .notAllowlisted,
             .premiumRequired, .rateLimited, .quotaExceeded, .network, .noActiveDevice, .notImplemented, .unexpected:
            true
        case .deviceRestricted, .contentRestricted, .playlistItemsUnavailable, .callbackPortInUse, .missingClientID,
             .cancelled, .playbackNotConfirmed, .notFound:
            false
        }
    }

    private func handle(_ event: LocalPlayerEvent) async {
        switch event {
        case .stateChanged(let state):
            localRunning = true
            applyLocal(state)
        case .launched:
            localRunning = true
            await refreshLocal()
        case .terminated:
            localRunning = false
            local = nil
            localRepeat = nil
            recompute()
            scheduleSync(after: .zero)
        }
    }

    private func refreshLocalAvailability() async {
        let status = await availability.run()
        localRunning = status.isRunning
        localPermission = status.permission
        if localDeviceName == nil { localDeviceName = await localPlayer.connectDeviceName() }
        recompute()
    }

    private func refreshLocal() async {
        await refreshLocalAvailability()
        guard localRunning else {
            local = nil
            recompute()
            return
        }
        await readLocalState()
    }

    private func readLocalState() async {
        guard localRunning, localPermission == .granted else { return }
        let epoch = commandEpoch
        do {
            let state = try await localPlayer.state()
            guard epoch == commandEpoch else { return }
            applyLocal(state)
        } catch {
            noteLocalFailure(error)
        }
    }

    private func applyLocal(_ incoming: LocalPlayerState) {
        var state = incoming
        let previous = local?.state
        // Notifications omit volume, shuffle and repeat; keep the last values Spotify reported for them.
        state.volume = state.volume ?? previous?.volume
        state.isShuffling = state.isShuffling ?? previous?.isShuffling
        state.isRepeating = state.isRepeating ?? previous?.isRepeating
        state.canShuffle = state.canShuffle ?? previous?.canShuffle
        state.canRepeat = state.canRepeat ?? previous?.canRepeat
        if state.track?.artworkURL == nil, previous?.track?.uri == state.track?.uri {
            state.track?.artworkURL = previous?.track?.artworkURL
        }
        local = LocalObservation(state: state, at: clock.now())
        let trackChanged = previous?.track?.uri != state.track?.uri
        // Only a value Spotify actually reported counts, never one carried over from an earlier read.
        let repeatNeedsWebAPI = incoming.isRepeating.map(foldLocalRepeat) ?? false
        recompute()
        notify(ObservedState(
            track: state.track?.uri,
            context: nil,
            isPlaying: state.status == .playing,
            position: state.position,
            isLocal: true
        ))
        // A skip to a queued song reconciles once at the end, not for each song it passes over.
        guard interfaceVisibility != .hidden, skipAheadID == nil else { return }
        if trackChanged {
            // AppleScript cannot say which context is playing or which device; one Web API read per track can.
            scheduleSync(after: .seconds(1))
            Task { await refreshSavedState() }
        } else if authority == .webAPI || repeatNeedsWebAPI {
            scheduleSync(after: .seconds(1))
        }
    }

    // Returns whether repeat came on without Orbit knowing which mode, which only the Web API can answer.
    private func foldLocalRepeat(_ repeating: Bool) -> Bool {
        observationCount += 1
        lastLocalRepeatRead = observationCount
        guard repeating else {
            localRepeat = .off
            return false
        }
        guard localRepeat == nil || localRepeat == .off else { return false }
        localRepeat = .context
        return true
    }

    private func foldRemoteRepeat(_ mode: RepeatMode, startedAt count: Int) {
        guard count < lastLocalRepeatRead else {
            localRepeat = mode
            return
        }
        // An AppleScript read landed while this one was in flight, so it is newer about on or off; this read can
        // still say which "on" it is.
        guard localRepeat != .off, mode != .off else { return }
        localRepeat = mode
    }

    private func refreshRemote() async {
        guard webUsable else {
            recompute()
            scheduleSync(after: nil)
            return
        }
        if let remoteFetch {
            await remoteFetch.value
            return
        }
        let epoch = commandEpoch
        let started = observationCount
        let task = Task { [weak self, api] in
            let result: Result<PlaybackSnapshot?, OrbitError>
            do throws(OrbitError) {
                result = .success(try await api.playbackState())
            } catch {
                result = .failure(error)
            }
            self?.finishRemoteFetch(result, epoch: epoch, startedAt: started)
        }
        remoteFetch = task
        await task.value
        remoteFetch = nil
        await refreshSavedState()
        scheduleSync(after: nil)
    }

    private func finishRemoteFetch(_ result: Result<PlaybackSnapshot?, OrbitError>, epoch: Int, startedAt started: Int) {
        switch result {
        case .success(let incoming):
            syncError = nil
            noteWebSuccess()
            // A command finished while this read was in flight, so it may describe the state before that command.
            guard epoch == commandEpoch else { return }
            contextSequence += 1
            remote = RemoteObservation(snapshot: incoming, at: clock.now(), sequence: contextSequence)
            if let device = incoming?.device, isLocalDevice(device) { localDeviceID = device.id }
            if let incoming, describesThisMac(incoming) { foldRemoteRepeat(incoming.repeatMode, startedAt: started) }
            recompute(freshRemote: true)
            notify(ObservedState(
                track: incoming?.track?.uri,
                context: incoming?.context?.uri,
                isPlaying: incoming?.isPlaying ?? false,
                position: incoming?.position,
                isLocal: false
            ))
        case .failure(let error):
            noteWebFailure(error)
            syncError = error
            recompute()
        }
    }

    private func refreshSavedState() async {
        guard let uri = snapshot.track?.uri, savedState?.uri != uri, webUsable else { return }
        do {
            let saved = try await api.libraryContains([uri]).contains(uri)
            savedState = (uri, saved)
            likedMembership = (uri, saved)
            noteWebSuccess()
            recompute()
        } catch {
            noteWebFailure(error)
        }
    }

    // Nil when unknown: the collection is loaded only when the user opens it, and the one-track check that fills
    // the heart has not answered for this track yet.
    private func isInLikedSongs(_ track: SpotifyURI, known context: SpotifyURI) -> Bool? {
        if let likedMembership, likedMembership.uri == track { return likedMembership.saved }
        return contextTracks?(context)?.contains(track)
    }

    private func noteWebFailure(_ error: OrbitError) {
        switch error {
        case .rateLimited(let retryAfter), .quotaExceeded(let retryAfter):
            webAPIPausedUntil = clock.now().addingTimeInterval(retryAfter ?? timing.defaultBackoff)
            webPauseReason = error
            syncError = error
            scheduleSync(after: nil)
        default:
            // Auth failures are left to the account store: the client signs out itself once the session is truly
            // gone, while a single rejected request must not stop syncing for the rest of the session.
            break
        }
    }

    // Spotify answering again ends any rate-limit or quota pause.
    private func noteWebSuccess() {
        guard webAPIPausedUntil != nil else { return }
        webAPIPausedUntil = nil
        webPauseReason = nil
    }

    private func noteLocalFailure(_ error: OrbitError) {
        switch error {
        case .automationDenied:
            localPermission = .denied
            automationDenied?()
        case .spotifyNotRunning:
            localRunning = false
            local = nil
        default:
            break
        }
        recompute()
    }

    // A Web API read about this Mac's playback: its device, or the very track the app reports.
    private func describesThisMac(_ remote: PlaybackSnapshot) -> Bool {
        if isLocalDevice(remote.device) { return true }
        guard let track = remote.track?.uri else { return false }
        return local?.state.track?.uri == track
    }

    private func isLocalDevice(_ device: PlaybackDevice?) -> Bool {
        guard let device else { return false }
        if let localDeviceID { return device.id == localDeviceID }
        return device.kind == .computer && device.name == localDeviceName
    }

    private func resolveAuthority() -> PlaybackRoute? {
        let remoteSnapshot = webSignedIn ? remote?.snapshot : nil
        let localState = localRunning ? local?.state : nil
        if let remoteSnapshot, let device = remoteSnapshot.device, !isLocalDevice(device),
           remoteSnapshot.isPlaying || localState?.status != .playing {
            return .webAPI
        }
        if localState != nil { return .local }
        return remoteSnapshot == nil ? nil : .webAPI
    }

    private func observedSnapshot() -> PlaybackSnapshot {
        let remoteSnapshot = webSignedIn ? remote?.snapshot : nil
        switch authority {
        case nil:
            return .idle
        case .webAPI:
            return remoteSnapshot.map(snapshotFromWebAPI) ?? .idle
        case .local:
            return local.map { snapshotFromLocal($0, remote: remoteSnapshot) } ?? .idle
        }
    }

    private func snapshotFromWebAPI(_ observed: PlaybackSnapshot) -> PlaybackSnapshot {
        var result = observed
        if let context = result.context {
            result.context = named(context)
        } else if let known = knownContext, LikedSongs.isLikedSongs(known.context.uri), let track = result.track?.uri,
                  isInLikedSongs(track, known: known.context.uri) ?? true {
            // Liked Songs started as a track list still belongs to Liked Songs for as long as it plays saved tracks.
            // What plays after Orbit started it is almost always one of them, so a track not answered for yet
            // counts as saved until the check that fills the heart says otherwise.
            result.context = known.context
        }
        return result
    }

    // AppleScript reports no context, device or repeat-one, so those come from a Web API read of the same track or
    // of this Mac, and fields the notification omits fall back to the previous observation.
    private func snapshotFromLocal(_ local: LocalObservation, remote remoteSnapshot: PlaybackSnapshot?) -> PlaybackSnapshot {
        let state = local.state
        let paired = remoteSnapshot.flatMap { $0.track?.uri == state.track?.uri && state.track != nil ? $0 : nil }
        var track = state.track
        if let richer = paired?.track {
            // The app names a larger copy of the same cover. Keeping the URL already on screen spares a second
            // download and decode per track change, since every view downsamples to well under either size.
            let artwork = track?.artworkURL
            track = richer
            if let artwork { track?.artworkURL = artwork }
        }
        // A track change seen locally before the next Web API read keeps the context it was playing in.
        let sameDevice = remoteSnapshot.flatMap { isLocalDevice($0.device) ? $0 : nil }
        var context = (paired ?? sameDevice)?.context.map { named($0) }
        if let known = knownContext, known.sequence > (remote?.sequence ?? -1) || context == nil {
            context = known.context
        }
        let volume = state.volume ?? paired?.volume
        var device = paired?.device ?? sameDevice?.device
            ?? PlaybackDevice(id: localDeviceID ?? "orbit.local-device", name: localDeviceName ?? "This Mac", kind: .computer)
        device.isActive = true
        device.volumePercent = volume
        // Never the published snapshot: it carries optimistic values, which must not become observed ones.
        return PlaybackSnapshot(
            track: track,
            isPlaying: state.status == .playing,
            position: state.position ?? 0,
            sampledAt: local.at,
            shuffle: state.isShuffling ?? (paired ?? sameDevice)?.shuffle ?? false,
            repeatMode: localRepeat ?? .off,
            context: context,
            device: device,
            volume: volume
        )
    }

    private func named(_ context: PlaybackContext) -> PlaybackContext {
        guard context.name == nil else { return context }
        var named = context
        named.name = (knownContext?.context.uri == context.uri ? knownContext?.context.name : nil) ?? contextName?(context.uri)
        return named
    }

    private func availableActions(for snapshot: PlaybackSnapshot) -> Set<PlaybackAction> {
        let web = webUsable
        let remoteActions = web ? remote?.snapshot?.availableActions : nil
        var actions: Set<PlaybackAction>
        switch authority {
        case nil:
            return []
        case .webAPI:
            guard web, let device = snapshot.device, !device.isRestricted else { return [] }
            actions = remoteActions ?? []
            if !device.supportsVolume { actions.remove(.setVolume) }
            return actions
        case .local:
            let state = local?.state
            if localCommandsUsable {
                actions = [.pause, .resume, .seek, .skipNext, .skipPrevious, .setVolume]
                if state?.canShuffle != false { actions.insert(.toggleShuffle) }
                if state?.canRepeat != false { actions.insert(.toggleRepeatContext) }
            } else if web {
                actions = remoteActions ?? [.pause, .resume, .seek, .skipNext, .skipPrevious, .toggleShuffle, .toggleRepeatContext, .setVolume]
            } else {
                actions = []
            }
            if web {
                actions.insert(.transfer)
                if actions.contains(.toggleRepeatContext) { actions.insert(.toggleRepeatTrack) }
            }
            if snapshot.track == nil { actions.subtract([.seek, .skipNext, .skipPrevious]) }
            return actions
        }
    }

    // `freshRemote` marks a Web API read that started after the last command finished, the only observation known
    // to postdate every intent; notifications carry no timestamp, so local overlays simply run out their grace.
    private func recompute(freshRemote: Bool = false) {
        authority = resolveAuthority()
        var result = observedSnapshot()
        let now = clock.now()
        // Overlays touch overlapping fields (a pause also freezes the position), so the newest intent applies last.
        for (field, overlay) in overlays.sorted(by: { $0.value.id < $1.value.id }) {
            if let expiresAt = overlay.expiresAt, now >= expiresAt || (freshRemote && overlay.isSatisfied(result)) {
                overlays[field] = nil
            } else {
                overlay.apply(&result)
            }
        }
        result.availableActions = availableActions(for: result)
        if result != snapshot { snapshot = result }
        scheduleOverlayExpiry()
    }

    private func scheduleOverlayExpiry() {
        overlayExpiry?.cancel()
        guard let next = overlays.values.compactMap(\.expiresAt).min() else { return }
        let delay = max(0, next.timeIntervalSince(clock.now()))
        overlayExpiry = Task { [weak self, clock] in
            do { try await clock.sleep(.seconds(delay)) } catch { return }
            guard let self else { return }
            self.overlayExpiry = nil
            self.recompute()
            // A notification that was stale on arrival may be the last thing observed; read back the truth.
            if self.authority == .local { await self.readLocalState() }
        }
    }

    // Keeps the earliest requested sync; `nil` means "whatever the regular interval says".
    private func scheduleSync(after requested: Duration?) {
        let regular = Self.syncDelay(
            visibility: interfaceVisibility,
            authority: authority,
            untilTrackEnds: snapshot.isPlaying ? snapshot.track.map { $0.duration - snapshot.position(at: clock.now()) } : nil,
            frequency: syncFrequency
        )
        guard webSignedIn, var delay = [requested, regular].compactMap({ $0 }).min() else {
            cancelScheduledSync()
            return
        }
        let now = clock.now()
        if let until = webAPIPausedUntil, until > now {
            delay = max(delay, .seconds(until.timeIntervalSince(now)))
        }
        let due = now.addingTimeInterval(delay.timeInterval)
        if let scheduledSync, scheduledSync.due <= due { return }
        cancelScheduledSync()
        let task = Task { [weak self, clock] in
            do { try await clock.sleep(delay) } catch { return }
            guard let self else { return }
            self.scheduledSync = nil
            await self.refreshRemote()
        }
        scheduledSync = (due, task)
    }

    private func cancelScheduledSync() {
        scheduledSync?.task.cancel()
        scheduledSync = nil
    }

    private func addPending(_ intent: PlaybackIntent) {
        pendingCounts[intent, default: 0] += 1
    }

    private func removePending(_ intent: PlaybackIntent) {
        let count = (pendingCounts[intent] ?? 1) - 1
        pendingCounts[intent] = count > 0 ? count : nil
    }

    private func enqueue<Value: Sendable>(_ body: @escaping @MainActor () async -> Value) async -> Value {
        let previous = commandTail
        let task = Task { @MainActor in
            await previous?.value
            return await body()
        }
        commandTail = Task { _ = await task.value }
        return await task.value
    }

    private func routes(local: LocalCommand?, web: WebCommand?, preferring preference: RoutePreference) -> [PlaybackRoute] {
        var available: [PlaybackRoute] = []
        if local != nil, localCommandsUsable { available.append(.local) }
        if web != nil, webUsable { available.append(.webAPI) }
        return authority == .webAPI || preference == .webAPI ? available.reversed() : available
    }

    // A command for this Mac's app, rather than for whichever device the Web API considers active.
    private var targetsThisMac: Bool {
        localRunning && authority != .webAPI
    }

    // This Mac's Spotify Connect device: the one Web API state last showed playing here, else the only computer in
    // the device list under this Mac's name. Nil when the app is missing from the list (offline, or signed in to
    // another account) or when another computer has the same name, since neither can be told apart from here.
    private func thisMacDeviceID() async -> String? {
        if let localDeviceID { return localDeviceID }
        if localDeviceName == nil { localDeviceName = await localPlayer.connectDeviceName() }
        guard let name = localDeviceName else { return nil }
        do {
            let matches = try await api.devices().filter { $0.kind == .computer && $0.name == name }
            noteWebSuccess()
            guard matches.count == 1 else { return nil }
            localDeviceID = matches[0].id
            return matches[0].id
        } catch {
            noteWebFailure(error)
            return nil
        }
    }

    private func unavailableError(local: LocalCommand?) -> OrbitError {
        if local != nil, localRunning, localPermission == .denied { return .automationDenied }
        if !localRunning, !webSignedIn { return .spotifyNotRunning }
        if webSignedIn { return webUnavailableError }
        return .notSignedIn
    }

    // Sends one command over the best route and falls back to the other when that route is unusable.
    private func deliver(
        local: LocalCommand?,
        web: WebCommand?,
        preferring preference: RoutePreference = .local
    ) async -> Result<PlaybackRoute, OrbitError> {
        var order = routes(local: local, web: web, preferring: preference)
        guard !order.isEmpty else { return .failure(unavailableError(local: local)) }
        // Without a device ID the Web API acts on the active device, which an idle app on this Mac is not. When this
        // Mac cannot be identified, the app is told directly instead.
        var device: String?
        if preference == .webAPI, order.first == .webAPI, targetsThisMac {
            device = await thisMacDeviceID()
            if device == nil, order.contains(.local) { order.removeFirst() }
        }
        var failure: OrbitError = .unexpected(detail: "No route")
        for route in order {
            do throws(OrbitError) {
                switch route {
                case .local:
                    try await Self.typed { [localPlayer] in try await local?(localPlayer) }
                    localPermission = .granted
                case .webAPI:
                    try await sendWeb(web, to: device)
                    noteWebSuccess()
                }
                return .success(route)
            } catch {
                failure = error
                if route == .local { noteLocalFailure(error) } else { noteWebFailure(error) }
                guard Self.isRouteFailure(error) else { break }
            }
        }
        if failure == .noActiveDevice, !localRunning { failure = .spotifyNotRunning }
        return .failure(failure)
    }

    private func sendWeb(_ web: WebCommand?, to device: String?) async throws(OrbitError) {
        guard let web else { return }
        if let device {
            do {
                try await Self.typed { [api] in try await web(api, device) }
            } catch .noActiveDevice {
                // Spotify answers "Device not found" to an ID it no longer knows, as after the app signs in again.
                localDeviceID = nil
                guard let current = await thisMacDeviceID(), current != device else { throw .noActiveDevice }
                try await Self.typed { [api] in try await web(api, current) }
            }
            return
        }
        do {
            try await Self.typed { [api] in try await web(api, nil) }
        } catch .noActiveDevice {
            // Nothing is active, so start on the device the user chose in settings if it is still around.
            guard let preferred = preferredDeviceID?() else { throw .noActiveDevice }
            try await Self.typed { [api] in try await web(api, preferred) }
        }
    }

    private static func typed(_ body: () async throws -> Void) async throws(OrbitError) {
        do {
            try await body()
        } catch let error as OrbitError {
            throw error
        } catch {
            throw .unexpected(detail: String(describing: error))
        }
    }

    private func run(
        _ intent: PlaybackIntent,
        overlay: (field: Field, apply: (inout PlaybackSnapshot) -> Void, isSatisfied: (PlaybackSnapshot) -> Bool)?,
        coalesces: Bool = false,
        waitsForTrackChange: Bool = false,
        preferring preference: RoutePreference = .local,
        local: LocalCommand?,
        web: WebCommand?
    ) async {
        let id = nextCommandID()
        latestIntent[intent] = id
        if let overlay {
            overlays[overlay.field] = Overlay(id: id, apply: overlay.apply, isSatisfied: overlay.isSatisfied)
            recompute()
        }
        addPending(intent)
        defer { removePending(intent) }
        await enqueue { [self] in
            // A newer intent of the same kind is already queued; it carries the value the user wants now.
            if coalesces, latestIntent[intent] != id { return }
            if waitsForTrackChange, let skip = skipInFlight {
                _ = await waitFor(timeout: timing.trackChangeTimeout) { $0.track != skip.from }
            }
            await send(id, field: overlay?.field, preferring: preference, local: local, web: web)
        }
    }

    // Skips are never coalesced: three presses mean three tracks.
    private func changeTrack(_ intent: PlaybackIntent, local: @escaping LocalCommand, web: @escaping WebCommand) async {
        addPending(intent)
        defer { removePending(intent) }
        let id = nextCommandID()
        await enqueue { [self] in
            skipInFlight = (snapshot.track?.uri, id)
            let result = await send(id, field: nil, local: local, web: web)
            if case .failure = result, skipInFlight?.id == id { skipInFlight = nil }
        }
    }

    private func nextCommandID() -> Int {
        lastCommandID += 1
        return lastCommandID
    }

    // Delivers a queued command, then gives its overlay a grace period on success or drops it on failure.
    @discardableResult
    private func send(
        _ id: Int,
        field: Field?,
        preferring preference: RoutePreference = .local,
        local: LocalCommand?,
        web: WebCommand?
    ) async -> Result<PlaybackRoute, OrbitError> {
        let result = await deliver(local: local, web: web, preferring: preference)
        commandEpoch += 1
        switch result {
        case .success(let route):
            lastError = nil
            if let field, overlays[field]?.id == id {
                let grace = route == .local ? timing.localOverlayGrace : timing.overlayGrace
                overlays[field]?.expiresAt = clock.now().addingTimeInterval(grace.timeInterval)
            }
            recompute()
            if route == .local {
                // Reading back right away reconciles within milliseconds instead of waiting for the notification.
                await readLocalState()
            } else if let field, overlays[field]?.id == id {
                confirmThroughWebAPI(field, id: id)
            } else {
                scheduleSync(after: timing.webSettleDelay)
            }
        case .failure(let error):
            if let field, overlays[field]?.id == id { overlays[field] = nil }
            lastError = error
            recompute()
        }
        return result
    }

    // The Web API can trail a command it accepted by more than the settle delay, and a read that still shows the old
    // value would otherwise stand once the grace period ends; so it is read again until it agrees or the grace ends.
    private func confirmThroughWebAPI(_ field: Field, id: Int) {
        Task { [weak self, clock, timing] in
            var waited = Duration.zero
            var delay = timing.webSettleDelay
            while waited + delay < timing.overlayGrace {
                do { try await clock.sleep(delay) } catch { return }
                waited += delay
                guard let self, self.overlays[field]?.id == id else { return }
                await self.refreshRemote()
                delay = .seconds(1)
            }
        }
    }

    // Issues a play command, then waits for observed state to show it before reporting success.
    private func start(
        _ intent: PlaybackIntent,
        local: @escaping LocalCommand,
        web: @escaping WebCommand,
        confirmed: @escaping (ObservedState, SpotifyURI?) -> Bool,
        onSuccess: @escaping () -> Void
    ) async -> Bool {
        switchGeneration += 1
        let generation = switchGeneration
        // A newer switch replaces this one; the older one ends quietly instead of reporting a failure.
        if let switchWaiterID { resolveWaiter(switchWaiterID, with: false) }
        addPending(intent)
        defer { removePending(intent) }
        let sent: SentCommand? = await enqueue { [self] in
            guard generation == switchGeneration else { return nil }
            let before = snapshot.track?.uri
            let wasShowing = localCommandsUsable ? await localPlayer.isShowingWindow() : true
            let result = await deliver(local: local, web: web, preferring: .webAPI)
            commandEpoch += 1
            if result == .success(.local), !wasShowing { tuckSpotifyAway() }
            return SentCommand(trackBefore: before, result: result)
        }
        guard let sent, generation == switchGeneration else { return false }
        if case .failure(let error) = sent.result {
            lastError = error
            return false
        }
        // Both start once the waiter below is registered, since this actor only yields when it suspends.
        let poller = webUsable ? Task { [weak self] in await self?.pollUntilConfirmed() } : nil
        // This Mac's app may have changed before the waiter was registered, whichever route started it.
        let readsLocal = sent.result == .success(.local) || (sent.result == .success(.webAPI) && targetsThisMac)
        let reader = readsLocal ? Task { [weak self] in await self?.readLocalState() } : nil
        defer { reader?.cancel() }
        let seen = await waitFor(timeout: timing.confirmationTimeout, register: { self.switchWaiterID = $0 }) {
            confirmed($0, sent.trackBefore)
        }
        poller?.cancel()
        guard generation == switchGeneration else { return false }
        guard seen else {
            lastError = .playbackNotConfirmed
            return false
        }
        lastError = nil
        onSuccess()
        recompute()
        return true
    }

    // `play track` makes Spotify navigate to the item and bring its window up, un-minimizing it, a moment after the
    // command returns. Nothing short of Accessibility or System Events can minimize it again, so the most Orbit can
    // do is hide the app as Command-H would. That takes the window off screen, but it is no longer minimized when
    // Spotify is next opened, it still shows the item, and if Spotify took focus, macOS picks the app that gets it
    // back. The check repeats briefly because the window can appear after the first look.
    private func tuckSpotifyAway() {
        let player = localPlayer
        Task { [clock] in
            for delay in [0, 0.25, 0.75, 1.5] {
                do { try await clock.sleep(.seconds(delay)) } catch { return }
                if await player.isShowingWindow() { await player.hide() }
            }
        }
    }

    // The Web API reflects a new context a moment after the command; a few spaced reads catch it without polling hard.
    private func pollUntilConfirmed(delays: [TimeInterval] = [0.4, 0.8, 1.5, 2.5]) async {
        for delay in delays {
            do { try await clock.sleep(.seconds(delay)) } catch { return }
            if Task.isCancelled { return }
            await refreshRemote()
        }
    }

    // Returns whether playback was seen on `target`; without one it only reads back where playback stopped.
    // Spotify posts its notifications in order, so the one naming the target arrives after those for the songs
    // passed over: waiting for it, rather than reading at once, means none of them can land afterwards and show a
    // song already skipped. The state read is only the fallback for a notification that does not come. On the Web
    // API, a few spaced reads stop at the first one showing the target.
    private func reconcileSkips(over route: PlaybackRoute, reaching target: SpotifyURI?) async -> Bool {
        guard let target else {
            if route == .local { await readLocalState() } else { scheduleSync(after: timing.webSettleDelay) }
            return false
        }
        if route == .local, local?.state.track?.uri == target { return true }
        // Either starts once the waiter below is registered, since this actor only yields when it suspends.
        let reads = route == .local
            ? Task { [weak self, clock, timing] in
                do { try await clock.sleep(timing.notificationGrace) } catch { return }
                await self?.readLocalState()
            }
            : Task { [weak self, timing] in
                await self?.pollUntilConfirmed(delays: [timing.webSettleDelay.timeInterval, 1, 1.5, 2.5])
            }
        defer { reads.cancel() }
        let timeout = route == .local ? timing.trackChangeTimeout : timing.confirmationTimeout
        return await waitFor(timeout: timeout) { $0.track == target }
    }

    private func adopt(context uri: SpotifyURI, name: String?) {
        let context = PlaybackContext(uri: uri, name: name ?? contextName?(uri))
        contextSequence += 1
        knownContext = (context, contextSequence)
    }

    private func waitFor(
        timeout: Duration,
        register: ((Int) -> Void)? = nil,
        _ matches: @escaping (ObservedState) -> Bool
    ) async -> Bool {
        nextWaiterID += 1
        let id = nextWaiterID
        register?(id)
        let timer = Task { [weak self, clock] in
            do { try await clock.sleep(timeout) } catch { return }
            self?.resolveWaiter(id, with: false)
        }
        let result = await withCheckedContinuation { continuation in
            waiters[id] = Waiter(matches: matches, continuation: continuation)
        }
        timer.cancel()
        return result
    }

    private func resolveWaiter(_ id: Int, with value: Bool) {
        waiters.removeValue(forKey: id)?.continuation.resume(returning: value)
    }

    private func notify(_ observation: ObservedState) {
        if let skip = skipInFlight, observation.track != skip.from { skipInFlight = nil }
        for (id, waiter) in waiters where waiter.matches(observation) {
            resolveWaiter(id, with: true)
        }
    }
}
