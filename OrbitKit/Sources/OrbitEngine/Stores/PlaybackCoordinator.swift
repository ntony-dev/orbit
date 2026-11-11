import Foundation
import Observation
import OrbitCore

public enum PlaybackIntent: Hashable, Sendable {
    case playPause, next, previous, seek, volume, shuffle, repeatMode, toggleSaved
    case playContext(SpotifyURI)
    case playTrack(SpotifyURI)
    case transfer(deviceID: String)
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
// playing, or the app is closed, the Web API snapshot is authoritative. Commands go to the authoritative side
// first and fall back to the other when that route is unavailable.
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
        public var defaultBackoff: TimeInterval = 30

        public init() {}
    }

    public private(set) var snapshot: PlaybackSnapshot = .idle
    // Intents sent but not yet confirmed, so the UI can show progress on exactly the control that was used.
    public private(set) var pendingIntents: Set<PlaybackIntent> = []
    public private(set) var isCurrentTrackSaved: Bool?
    public private(set) var lastError: OrbitError?
    // Which side `snapshot` comes from; nil when nothing is playing anywhere Orbit can see.
    public private(set) var authority: PlaybackRoute?
    public private(set) var interfaceVisibility: InterfaceVisibility = .collapsed
    // Set while Spotify rate limits Orbit or the quota is spent; local controls keep working meanwhile.
    public private(set) var webAPIPausedUntil: Date?
    // The last failure of background syncing, kept apart from `lastError` so polling never interrupts the user.
    public private(set) var syncError: OrbitError?

    @ObservationIgnored var contextStarted: ((Playlist) -> Void)?
    @ObservationIgnored var contextName: ((SpotifyURI) -> String?)?
    // Known track URIs of a context, used to tell a confirmed switch from an unrelated track change.
    @ObservationIgnored var contextTracks: ((SpotifyURI) -> Set<SpotifyURI>?)?
    @ObservationIgnored var preferredDeviceID: (() -> String?)?
    @ObservationIgnored var automationDenied: (() -> Void)?

    @ObservationIgnored private let localPlayer: any LocalPlayer
    @ObservationIgnored private let api: any SpotifyAPI
    @ObservationIgnored private let clock: EngineClock
    @ObservationIgnored private let timing: Timing

    @ObservationIgnored private var local: LocalObservation?
    @ObservationIgnored private var localRunning = false
    @ObservationIgnored private var localPermission = AutomationPermission.notDetermined
    @ObservationIgnored private var localDeviceName: String?
    @ObservationIgnored private var localDeviceID: String?
    @ObservationIgnored private var remote: RemoteObservation?
    // The context Orbit itself confirmed starting, ordered against Web API reads by `contextSequence`.
    @ObservationIgnored private var knownContext: (context: PlaybackContext, sequence: Int)?
    @ObservationIgnored private var contextSequence = 0
    @ObservationIgnored private var webSignedIn = true

    @ObservationIgnored private var overlays: [Field: Overlay] = [:]
    @ObservationIgnored private var nextOverlayID = 0
    @ObservationIgnored private var pendingCounts: [PlaybackIntent: Int] = [:]
    @ObservationIgnored private var latestIntent: [PlaybackIntent: Int] = [:]
    @ObservationIgnored private var commandTail: Task<Void, Never>?
    @ObservationIgnored private var commandEpoch = 0
    // Set while a skip is in flight, so a seek issued meanwhile lands on the new track rather than the old one.
    @ObservationIgnored private var skipInFlight: (from: SpotifyURI?, id: Int)?
    @ObservationIgnored private var switchGeneration = 0
    @ObservationIgnored private var switchWaiterID: Int?
    @ObservationIgnored private var webPauseReason: OrbitError?

    @ObservationIgnored private var waiters: [Int: Waiter] = [:]
    @ObservationIgnored private var nextWaiterID = 0

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var remoteFetch: Task<Void, Never>?
    @ObservationIgnored private var scheduledSync: (due: Date, task: Task<Void, Never>)?
    @ObservationIgnored private var overlayExpiry: Task<Void, Never>?
    @ObservationIgnored private var savedState: (uri: SpotifyURI, saved: Bool)?

    public init(localPlayer: any LocalPlayer, api: any SpotifyAPI, clock: EngineClock = .system, timing: Timing = Timing()) {
        self.localPlayer = localPlayer
        self.api = api
        self.clock = clock
        self.timing = timing
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
            savedState = nil
            isCurrentTrackSaved = nil
        }
        recompute()
        scheduleSync(after: available ? .zero : nil)
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

    // AppleScript only knows repeat on or off, so repeat-one always goes through the Web API.
    public func setRepeat(_ mode: RepeatMode) async {
        var local: LocalCommand?
        if mode != .track {
            local = { player in try await player.setRepeating(mode == .context) }
        }
        await run(
            .repeatMode,
            overlay: (.repeatMode, { $0.repeatMode = mode }, { $0.repeatMode == mode }),
            coalesces: true,
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
        isCurrentTrackSaved = !saved
        addPending(.toggleSaved)
        defer { removePending(.toggleSaved) }
        do {
            if saved {
                try await api.removeFromLibrary([uri])
            } else {
                try await api.saveToLibrary([uri])
            }
            savedState = (uri, !saved)
        } catch {
            noteWebFailure(error)
            if snapshot.track?.uri == uri { isCurrentTrackSaved = saved }
            lastError = error
        }
    }

    // Plain-value rule for how often to sync from the Web API; nil means only on events.
    static func syncDelay(
        visibility: InterfaceVisibility,
        authority: PlaybackRoute?,
        untilTrackEnds: TimeInterval?
    ) -> Duration? {
        let base: TimeInterval? = switch (visibility, authority) {
        case (.hidden, _): nil
        case (.expanded, .webAPI): 5
        case (.collapsed, .webAPI): 15
        case (.expanded, .local): 30
        case (.collapsed, .local): nil
        case (.expanded, nil): 10
        case (.collapsed, nil): 60
        }
        guard let base else { return nil }
        guard authority == .webAPI, let remaining = untilTrackEnds else { return .seconds(base) }
        return .seconds(max(1, min(base, remaining + 1)))
    }
}

extension PlaybackCoordinator {
    private enum Field: Hashable {
        case playing, position, shuffle, repeatMode, volume, device
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

    struct ObservedState {
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

    // Untyped so command closures stay one-liners; every service behind them throws OrbitError.
    typealias LocalCommand = @Sendable (any LocalPlayer) async throws -> Void
    typealias WebCommand = @Sendable (any SpotifyAPI, String?) async throws -> Void

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
             .cancelled, .playbackNotConfirmed:
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
            recompute()
            scheduleSync(after: .zero)
        }
    }

    private func refreshLocalAvailability() async {
        localRunning = await localPlayer.isRunning()
        localPermission = localRunning ? await localPlayer.automationPermission(prompting: false) : .requiresSpotifyRunning
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
        recompute()
        notify(ObservedState(
            track: state.track?.uri,
            context: nil,
            isPlaying: state.status == .playing,
            position: state.position,
            isLocal: true
        ))
        if trackChanged, interfaceVisibility != .hidden {
            // AppleScript cannot say which context is playing or which device; one Web API read per track can.
            scheduleSync(after: .seconds(1))
            Task { await refreshSavedState() }
        } else if authority == .webAPI {
            scheduleSync(after: .seconds(1))
        }
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
        let task = Task { [weak self, api] in
            let result: Result<PlaybackSnapshot?, OrbitError>
            do throws(OrbitError) {
                result = .success(try await api.playbackState())
            } catch {
                result = .failure(error)
            }
            self?.finishRemoteFetch(result, epoch: epoch)
        }
        remoteFetch = task
        await task.value
        remoteFetch = nil
        if snapshot.track?.uri != savedState?.uri { await refreshSavedState() }
        scheduleSync(after: nil)
    }

    private func finishRemoteFetch(_ result: Result<PlaybackSnapshot?, OrbitError>, epoch: Int) {
        switch result {
        case .success(let incoming):
            syncError = nil
            // A command finished while this read was in flight, so it may describe the state before that command.
            guard epoch == commandEpoch else { return }
            contextSequence += 1
            remote = RemoteObservation(snapshot: incoming, at: clock.now(), sequence: contextSequence)
            if let device = incoming?.device, isLocalDevice(device) { localDeviceID = device.id }
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
        guard let uri = snapshot.track?.uri, webUsable else {
            if snapshot.track == nil { isCurrentTrackSaved = nil }
            return
        }
        if let savedState, savedState.uri == uri {
            isCurrentTrackSaved = savedState.saved
            return
        }
        do {
            let saved = try await api.libraryContains([uri]).contains(uri)
            savedState = (uri, saved)
            if snapshot.track?.uri == uri { isCurrentTrackSaved = saved }
        } catch {
            noteWebFailure(error)
            if snapshot.track?.uri == uri { isCurrentTrackSaved = nil }
        }
    }

    private func noteWebFailure(_ error: OrbitError) {
        switch error {
        case .rateLimited(let retryAfter), .quotaExceeded(let retryAfter):
            webAPIPausedUntil = clock.now().addingTimeInterval(retryAfter ?? timing.defaultBackoff)
            webPauseReason = error
            syncError = error
            scheduleSync(after: nil)
        case .notSignedIn, .authExpired:
            webSignedIn = false
        default:
            break
        }
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
            guard var result = remoteSnapshot else { return .idle }
            if let context = result.context {
                result.context = named(context)
            }
            return result
        case .local:
            guard let local else { return .idle }
            let state = local.state
            let paired = remoteSnapshot.flatMap { $0.track?.uri == state.track?.uri && state.track != nil ? $0 : nil }
            var track = state.track
            if let richer = paired?.track {
                let artwork = track?.artworkURL
                track = richer
                if track?.artworkURL == nil { track?.artworkURL = artwork }
            }
            // A track change seen locally before the next Web API read keeps the context it was playing in.
            let sameDevice = remoteSnapshot.flatMap { isLocalDevice($0.device) ? $0 : nil }
            var context = (paired ?? sameDevice)?.context.map { named($0) }
            if let known = knownContext, known.sequence > (remote?.sequence ?? -1) || context == nil {
                context = known.context
            }
            let volume = state.volume ?? paired?.volume
            var device = paired?.device ?? remoteSnapshot?.device.flatMap { isLocalDevice($0) ? $0 : nil }
                ?? PlaybackDevice(id: localDeviceID ?? Self.localDevicePlaceholderID, name: localDeviceName ?? "This Mac", kind: .computer)
            device.isActive = true
            device.volumePercent = volume
            let repeatMode: RepeatMode = switch state.isRepeating {
            case true?: (paired?.repeatMode ?? snapshot.repeatMode) == .track ? .track : .context
            case false?: .off
            case nil: paired?.repeatMode ?? snapshot.repeatMode
            }
            return PlaybackSnapshot(
                track: track,
                isPlaying: state.status == .playing,
                position: state.position ?? 0,
                sampledAt: local.at,
                shuffle: state.isShuffling ?? paired?.shuffle ?? snapshot.shuffle,
                repeatMode: repeatMode,
                context: context,
                device: device,
                volume: volume
            )
        }
    }

    static let localDevicePlaceholderID = "orbit.local-device"

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
        for (field, overlay) in overlays {
            if let expiresAt = overlay.expiresAt, now >= expiresAt || (freshRemote && overlay.isSatisfied(result)) {
                overlays[field] = nil
            } else {
                overlay.apply(&result)
            }
        }
        result.availableActions = availableActions(for: result)
        if result != snapshot { snapshot = result }
        if isCurrentTrackSaved != nil, snapshot.track?.uri != savedState?.uri { isCurrentTrackSaved = nil }
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
            untilTrackEnds: snapshot.isPlaying ? snapshot.track.map { $0.duration - snapshot.position(at: clock.now()) } : nil
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
        pendingIntents.insert(intent)
    }

    private func removePending(_ intent: PlaybackIntent) {
        let count = (pendingCounts[intent] ?? 1) - 1
        pendingCounts[intent] = count > 0 ? count : nil
        if count <= 0 { pendingIntents.remove(intent) }
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

    private func routes(local: LocalCommand?, web: WebCommand?) -> [PlaybackRoute] {
        var available: [PlaybackRoute] = []
        if local != nil, localCommandsUsable { available.append(.local) }
        if web != nil, webUsable { available.append(.webAPI) }
        return authority == .webAPI ? available.reversed() : available
    }

    private func unavailableError(local: LocalCommand?) -> OrbitError {
        if local != nil, localRunning, localPermission == .denied { return .automationDenied }
        if !localRunning, !webSignedIn { return .spotifyNotRunning }
        if webSignedIn { return webUnavailableError }
        return .notSignedIn
    }

    // Sends one command over the best route and falls back to the other when that route is unusable.
    private func deliver(local: LocalCommand?, web: WebCommand?) async -> Result<PlaybackRoute, OrbitError> {
        let order = routes(local: local, web: web)
        guard !order.isEmpty else { return .failure(unavailableError(local: local)) }
        var failure: OrbitError = .unexpected(detail: "No route")
        for route in order {
            do throws(OrbitError) {
                switch route {
                case .local:
                    try await Self.typed { [localPlayer] in try await local?(localPlayer) }
                case .webAPI:
                    try await sendWeb(web)
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

    private func sendWeb(_ web: WebCommand?) async throws(OrbitError) {
        guard let web else { return }
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
        overlay: (Field, (inout PlaybackSnapshot) -> Void, (PlaybackSnapshot) -> Bool)?,
        coalesces: Bool = false,
        waitsForTrackChange: Bool = false,
        local: LocalCommand?,
        web: WebCommand?
    ) async {
        nextOverlayID += 1
        let id = nextOverlayID
        latestIntent[intent] = id
        if let overlay {
            overlays[overlay.0] = Overlay(id: id, apply: overlay.1, isSatisfied: overlay.2)
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
            let result = await deliver(local: local, web: web)
            settle(overlayID: id, field: overlay?.0, result: result)
            // Reading back right away reconciles within a few milliseconds instead of waiting for the notification.
            if case .success(.local) = result { await readLocalState() }
        }
    }

    private func settle(overlayID id: Int, field: Field?, result: Result<PlaybackRoute, OrbitError>) {
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
                localPermission = .granted
            } else {
                scheduleSync(after: timing.webSettleDelay)
            }
        case .failure(let error):
            if let field, overlays[field]?.id == id { overlays[field] = nil }
            lastError = error
            recompute()
        }
    }

    // Skips are never coalesced: three presses mean three tracks.
    private func changeTrack(_ intent: PlaybackIntent, local: @escaping LocalCommand, web: @escaping WebCommand) async {
        addPending(intent)
        defer { removePending(intent) }
        nextOverlayID += 1
        let id = nextOverlayID
        await enqueue { [self] in
            skipInFlight = (snapshot.track?.uri, id)
            let result = await deliver(local: local, web: web)
            if case .failure = result, skipInFlight?.id == id { skipInFlight = nil }
            settle(overlayID: id, field: nil, result: result)
            if case .success(.local) = result { await readLocalState() }
        }
    }

    private func play(context uri: SpotifyURI, name: String?) async -> Bool {
        let tracks = contextTracks?(uri)
        return await start(
            .playContext(uri),
            local: { try await $0.play(track: uri, inContext: nil) },
            web: { try await $0.play(LikedSongs.webTarget(for: uri), deviceID: $1) },
            confirmed: { observation, before in
                if let context = observation.context { return Self.sameContext(context, uri) }
                guard observation.isLocal, observation.isPlaying, let track = observation.track else { return false }
                if let tracks, !tracks.isEmpty { return tracks.contains(track) }
                return track != before || (observation.position ?? .infinity) < 3
            }
        ) { [weak self] in
            self?.adopt(context: uri, name: name)
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
            let result = await deliver(local: local, web: web)
            commandEpoch += 1
            if case .success(.local) = result { localPermission = .granted }
            return SentCommand(trackBefore: before, result: result)
        }
        guard let sent, generation == switchGeneration else { return false }
        if case .failure(let error) = sent.result {
            lastError = error
            return false
        }
        // Both start once the waiter below is registered, since this actor only yields when it suspends.
        let poller = webUsable ? Task { [weak self] in await self?.pollUntilConfirmed() } : nil
        let reader = sent.result == .success(.local) ? Task { [weak self] in await self?.readLocalState() } : nil
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

    // The Web API reflects a new context a moment after the command; a few spaced reads catch it without polling hard.
    private func pollUntilConfirmed() async {
        for delay in [0.4, 0.8, 1.5, 2.5] {
            do { try await clock.sleep(.seconds(delay)) } catch { return }
            if Task.isCancelled { return }
            await refreshRemote()
        }
    }

    private func adopt(context uri: SpotifyURI, name: String?) {
        let context = PlaybackContext(uri: uri, name: name ?? contextName?(uri))
        contextSequence += 1
        knownContext = (context, contextSequence)
    }

    static func sameContext(_ lhs: SpotifyURI, _ rhs: SpotifyURI) -> Bool {
        lhs == rhs || (LikedSongs.isLikedSongs(lhs) && LikedSongs.isLikedSongs(rhs))
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
