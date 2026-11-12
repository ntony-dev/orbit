import Foundation
import OrbitCore

// One simulated Spotify behind both the mock local player and the mock Web API, so commands sent through either
// show up in the other, as they do with the real desktop app and Spotify Connect.
public actor MockSpotify {
    public enum Window: Sendable {
        case visible, minimized, hidden
    }

    private let latency: Duration
    private let now: @Sendable () -> Date
    private let events = Broadcaster<LocalPlayerEvent>()
    private var clockTask: Task<Void, Never>?
    private var toggleTask: Task<Void, Never>?

    private var isRunning = true
    private var automationPermission = AutomationPermission.granted
    private var savedTracks: [Track]
    private var devices = MockFixtures.devices
    private var activeDeviceID: String? = MockFixtures.devices.first { $0.isActive }?.id
    // The Spotify Connect device the app on this Mac is.
    private var localDeviceID = MockFixtures.localDevice.id
    public private(set) var window = Window.visible
    // How often the app brought its window up, which only a local `play track` does.
    public private(set) var windowRaises = 0

    private var context: PlaybackContext?
    private var contextTracks: [Track] = []
    private var contextIndex = 0
    private var nowPlaying: Track?
    private var userQueue: [Track]
    private var isPlaying = false
    private var positionAtSample: TimeInterval = 0
    private var sampledAt: Date
    private var shuffle = false
    private var repeatMode = RepeatMode.off
    private var volume = 64

    private var playlists = MockFixtures.playlists
    private var commandsHeld = false
    // Names of the Web API reads that wait for `releaseHeld()`; nil holds none, an empty set holds all.
    private var heldReads: Set<String>?
    private var heldRequests: [CheckedContinuation<Void, Never>] = []
    private var webFailure: OrbitError?
    private var requestFailures: [String: OrbitError] = [:]
    private var lagArmed = 0
    private var laggedReads = 0
    private var laggedSnapshot: PlaybackSnapshot?
    private var localFailure: OrbitError?
    private var ignoresPlayCommands = false
    private(set) var rejectsLikedSongsContext = false
    private var pageSizeLimit: Int?
    private var reportsLargerLocalArtwork = false
    private var droppedFromPages: Set<String> = []
    // Every Web API request and AppleScript command, in order, so tests can assert routing and request counts.
    public private(set) var webRequests: [String] = []
    public private(set) var localCommands: [String] = []
    // Automation permission checks and AppleScript state reads, each a trip over the real app's serial channel.
    public private(set) var permissionChecks = 0
    public private(set) var stateReads = 0

    public init(latency: Duration = .milliseconds(120), now: @escaping @Sendable () -> Date = { .now }) {
        self.latency = latency
        self.now = now
        sampledAt = now()
        savedTracks = MockFixtures.savedTrackIDs.compactMap(MockFixtures.track(id:))
        userQueue = MockFixtures.queuedTrackIDs.compactMap(MockFixtures.track(id:))
        let first = MockFixtures.playlists[0]
        context = PlaybackContext(uri: first.uri)
        contextTracks = MockFixtures.playlistTracks[first.id] ?? []
        nowPlaying = contextTracks.first
        positionAtSample = (nowPlaying?.duration ?? 0) * 0.38
        isPlaying = true
    }

    // Advances the simulated clock once a second so tracks end and roll over while the demo runs.
    public func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.tick()
            }
        }
    }

    // Halfway between toggles the unchanged state is posted again, as the real app's later notifications and
    // Orbit's read-backs do, because a view that only settles on the next update looks right without one.
    public func startTogglingPlayback(every interval: Duration) {
        guard toggleTask == nil else { return }
        toggleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval / 2)
                await self?.togglePlaying()
                try? await Task.sleep(for: interval / 2)
                await self?.emitChange()
            }
        }
    }

    public func tick() {
        guard isPlaying, let track = nowPlaying, position >= track.duration else { return }
        if repeatMode == .track {
            restartCurrent()
        } else {
            advance(wrapping: repeatMode == .context)
        }
        emitChange()
    }

    // Quitting the app stops playback only when this Mac was the device playing.
    public func simulateQuit() {
        isRunning = false
        if activeDeviceID == localDeviceID { isPlaying = false }
        events.send(.terminated)
    }

    public func simulateLaunch() {
        isRunning = true
        events.send(.launched)
        emitChange()
    }

    public func setAutomationPermission(_ permission: AutomationPermission) {
        automationPermission = permission
    }

    // Commands wait here until `releaseHeld()`, so tests can interleave notifications with commands in flight.
    public func holdCommands() {
        commandsHeld = true
    }

    // Web API reads wait too, until `releaseHeld()`, so tests can act while a load is in flight. Pass names
    // such as "playlists" to hold only those requests.
    public func holdReads(_ names: Set<String> = []) {
        heldReads = names
    }

    public func releaseHeld() {
        commandsHeld = false
        heldReads = nil
        let held = heldRequests
        heldRequests.removeAll()
        held.forEach { $0.resume() }
    }

    public var heldRequestCount: Int { heldRequests.count }

    // Every Web API call throws this until cleared, e.g. `.rateLimited(retryAfter: 30)` or `.network(detail:)`.
    public func failWebAPI(with error: OrbitError?) {
        webFailure = error
    }

    // Only the named Web API request throws, e.g. "play" refused while state reads keep working.
    public func failWebRequest(_ name: String, with error: OrbitError?) {
        requestFailures[name] = error
    }

    public func failLocalCommands(with error: OrbitError?) {
        localFailure = error
    }

    // Play commands are accepted but nothing starts, as when Spotify silently refuses a context.
    public func ignorePlayCommands(_ ignores: Bool) {
        ignoresPlayCommands = ignores
    }

    // Pages like the real client: at most `size` raw entries each, with the given playlist or track IDs dropped
    // as Spotify's null and local entries are, so a page's next offset differs from its item count.
    public func pageLikeTheWebAPI(size: Int, dropping ids: Set<String>) {
        pageSizeLimit = size
        droppedFromPages = ids
    }

    // The real app reports a 640 px cover through AppleScript while the Web API names a smaller one of the same
    // image; this gives the local side its own URL for each cover.
    public func reportLargerLocalArtwork(_ reports: Bool) {
        reportsLargerLocalArtwork = reports
    }

    static func largerArtwork(_ track: Track?) -> Track? {
        guard var track, let url = track.artworkURL else { return track }
        track.artworkURL = URL(string: url.absoluteString + "#640")
        return track
    }

    func playlistsPage(_ request: PageRequest) -> Page<Playlist> {
        libraryPage(playlists, id: \.id, request)
    }

    // Spotify answers 400 to Liked Songs as a context, and the Web client plays the saved tracks as a list instead,
    // so playback state reports no context.
    public func rejectLikedSongsContext(_ rejects: Bool) {
        rejectsLikedSongsContext = rejects
    }

    // A collection the size of a long-time listener's, appended after the fixture tracks.
    public func addSavedTracks(count: Int) {
        savedTracks += (0..<count).map { index in
            Track(id: "saved-\(index)", name: "Saved Song \(index + 1)", artists: ["Various"], album: "Saved", duration: 200)
        }
    }

    public var savedTrackCount: Int { savedTracks.count }

    func savedTrackURIs(limit: Int) -> [SpotifyURI] {
        Array(savedTracks.prefix(limit).map(\.uri))
    }

    // Delivers a notification as if Spotify posted it, e.g. one that is stale by the time it arrives.
    public func emitLocalState(_ state: LocalPlayerState) {
        events.send(.stateChanged(state))
    }

    public func currentLocalState() -> LocalPlayerState? {
        try? localState()
    }

    // Another device takes over playback, as when the user presses play on their phone.
    public func simulateRemotePlayback(on deviceID: String) {
        guard devices.contains(where: { $0.id == deviceID }) else { return }
        activeDeviceID = deviceID
        isPlaying = nowPlaying != nil
        sampledAt = now()
        emitChange()
    }

    // The app on this Mac stays open with its track paused, but Spotify Connect no longer counts it as the active
    // device, as happens after it sits idle for a while: the Web API reports nothing playing.
    public func simulateIdleLocalDevice() {
        setPlaying(false)
        if activeDeviceID == localDeviceID { activeDeviceID = nil }
    }

    // The app on this Mac is missing from Spotify Connect, as when it is offline or signed in to another account.
    public func removeLocalDeviceFromConnect() {
        devices.removeAll { $0.id == localDeviceID }
        if activeDeviceID == localDeviceID { activeDeviceID = nil }
    }

    // Spotify gives the app on this Mac a new Connect device ID, as after it signs out and back in.
    public func changeLocalDeviceID(to id: String) {
        guard let index = devices.firstIndex(where: { $0.id == localDeviceID }) else { return }
        devices[index].id = id
        if activeDeviceID == localDeviceID { activeDeviceID = id }
        localDeviceID = id
    }

    // What Spotify is really doing, which AppleScript only reports as on or off.
    public var repeatState: RepeatMode { repeatMode }

    // The user changes repeat in Spotify's own window or on another device.
    public func simulateRepeatChangedInApp(_ mode: RepeatMode) {
        setRepeat(mode)
    }

    // After the next Web API command, this many playback state reads still describe the state before it, as the
    // real Web API can for a moment after a change.
    public func lagPlaybackState(reads: Int) {
        lagArmed = reads
    }

    func noteWebCommand() {
        guard lagArmed > 0 else { return }
        laggedSnapshot = snapshot()
        laggedReads = lagArmed
        lagArmed = 0
    }

    func playbackStateRead() -> PlaybackSnapshot? {
        guard laggedReads > 0 else { return snapshot() }
        laggedReads -= 1
        return laggedSnapshot
    }

    public func setWindow(_ window: Window) {
        self.window = window
    }

    // Like the real app opening a link: the window comes up even when it was minimized or the app hidden.
    func raiseWindow() {
        window = .visible
        windowRaises += 1
    }

    func hideApp() {
        guard isRunning, window == .visible else { return }
        window = .hidden
    }

    var isShowingWindow: Bool {
        isRunning && window == .visible
    }

    // A playlist the user deleted or unfollowed elsewhere disappears from the library.
    public func removePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
    }

    func libraryPlaylists() -> [Playlist] {
        playlists
    }

    func webRequest(_ name: String, isCommand: Bool = false) async throws(OrbitError) {
        webRequests.append(name)
        if isCommand {
            await awaitCommandTurn()
        } else {
            await simulateLatency()
            if let heldReads, heldReads.isEmpty || heldReads.contains(name) {
                await withCheckedContinuation { heldRequests.append($0) }
            }
        }
        if let webFailure { throw webFailure }
        if let failure = requestFailures[name] { throw failure }
    }

    func localCommand(_ name: String) async throws(OrbitError) {
        // Like the real player, a command asks for Automation permission if it was never asked; the user accepts.
        _ = resolvePermission(prompting: true)
        try requireRunning()
        localCommands.append(name)
        await awaitCommandTurn()
        try requireRunning()
        if let localFailure { throw localFailure }
    }

    private func awaitCommandTurn() async {
        await simulateLatency()
        guard commandsHeld else { return }
        await withCheckedContinuation { heldRequests.append($0) }
    }

    nonisolated func eventStream() -> AsyncStream<LocalPlayerEvent> {
        events.stream()
    }

    func simulateLatency() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }

    var running: Bool { isRunning }

    func permission(prompting: Bool) -> AutomationPermission {
        permissionChecks += 1
        return resolvePermission(prompting: prompting)
    }

    private func resolvePermission(prompting: Bool) -> AutomationPermission {
        guard isRunning else { return .requiresSpotifyRunning }
        if prompting, automationPermission == .notDetermined { automationPermission = .granted }
        return automationPermission
    }

    private var position: TimeInterval {
        guard isPlaying else { return positionAtSample }
        return min(nowPlaying?.duration ?? 0, positionAtSample + max(0, now().timeIntervalSince(sampledAt)))
    }

    private var activeDevice: PlaybackDevice? {
        devices.first { $0.id == activeDeviceID }.map {
            var device = $0
            device.isActive = true
            device.volumePercent = device.supportsVolume ? volume : nil
            return device
        }
    }

    func readLocalState() throws(OrbitError) -> LocalPlayerState {
        stateReads += 1
        return try localState()
    }

    func localState() throws(OrbitError) -> LocalPlayerState {
        try requireRunning()
        return LocalPlayerState(
            status: nowPlaying == nil ? .stopped : (isPlaying ? .playing : .paused),
            track: reportsLargerLocalArtwork ? Self.largerArtwork(nowPlaying) : nowPlaying,
            position: position,
            volume: volume,
            isShuffling: shuffle,
            isRepeating: repeatMode != .off
        )
    }

    private var activeDeviceReachable: Bool {
        isRunning || activeDeviceID != localDeviceID
    }

    func snapshot() -> PlaybackSnapshot? {
        guard activeDeviceReachable, let device = activeDevice, nowPlaying != nil else { return nil }
        var actions = Set(PlaybackAction.allCases)
        if !device.supportsVolume { actions.remove(.setVolume) }
        if device.isRestricted { actions = [] }
        return PlaybackSnapshot(
            track: nowPlaying,
            isPlaying: isPlaying,
            position: position,
            sampledAt: now(),
            shuffle: shuffle,
            repeatMode: repeatMode,
            context: context,
            device: device,
            volume: device.volumePercent,
            availableActions: actions
        )
    }

    func requireRunning() throws(OrbitError) {
        guard isRunning else { throw .spotifyNotRunning }
        guard automationPermission == .granted else { throw .automationDenied }
    }

    func requireControllableDevice() throws(OrbitError) {
        guard activeDeviceReachable, let device = activeDevice else { throw .noActiveDevice }
        guard !device.isRestricted else { throw .deviceRestricted }
    }

    func requireVolumeControl() throws(OrbitError) {
        guard activeDevice?.supportsVolume == true else { throw .deviceRestricted }
    }

    func setPlaying(_ playing: Bool) {
        guard nowPlaying != nil, playing != isPlaying else { return }
        positionAtSample = position
        sampledAt = now()
        isPlaying = playing
        emitChange()
    }

    func togglePlaying() {
        setPlaying(!isPlaying)
    }

    func next() {
        advance(wrapping: true)
        emitChange()
    }

    func previous() {
        if position > 3 || contextTracks.isEmpty {
            restartCurrent()
        } else {
            contextIndex = (contextIndex - 1 + contextTracks.count) % contextTracks.count
            start(contextTracks[contextIndex])
        }
        emitChange()
    }

    func seek(to seconds: TimeInterval) {
        positionAtSample = min(max(0, seconds), nowPlaying?.duration ?? 0)
        sampledAt = now()
        emitChange()
    }

    func setVolume(_ percent: Int) {
        volume = min(100, max(0, percent))
        emitChange()
    }

    func setShuffle(_ enabled: Bool) {
        shuffle = enabled
        emitChange()
    }

    func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        emitChange()
    }

    // AppleScript's boolean: turning it on while repeat-one is already on is modeled as leaving repeat-one alone.
    func setRepeating(_ enabled: Bool) {
        setRepeat(enabled ? (repeatMode == .off ? .context : repeatMode) : .off)
    }

    func play(_ target: PlayTarget) throws(OrbitError) {
        guard !ignoresPlayCommands else { return }
        switch target {
        case .context(let uri, let offset):
            // As the real Web API does, a playlist that no longer exists is a 404 rather than a refusal.
            guard let tracks = contextTracks(for: uri) else { throw uri.kind == .playlist ? .notFound : .contentRestricted }
            guard !tracks.isEmpty else { throw .contentRestricted }
            // Spotify never names the context in playback state; the engine fills names in from the library.
            context = PlaybackContext(uri: uri)
            contextTracks = tracks
            contextIndex = Self.index(of: offset, in: tracks)
        case .tracks(let uris, let offset):
            let tracks = uris.compactMap { uri in MockFixtures.tracks.first { $0.uri == uri } }
            guard !tracks.isEmpty else { throw .contentRestricted }
            context = nil
            contextTracks = tracks
            contextIndex = Self.index(of: offset, in: tracks)
        }
        start(contextTracks[contextIndex])
        emitChange()
    }

    // Like the real app, `play track` also accepts a playlist, album or Liked Songs URI and plays it as a context.
    func play(track uri: SpotifyURI, inContext contextURI: SpotifyURI?) throws(OrbitError) {
        if let contextURI {
            try play(.context(contextURI, offset: .track(uri)))
        } else if uri.kind == .track {
            try play(.tracks([uri]))
        } else {
            try play(.context(uri))
        }
    }

    private func contextTracks(for uri: SpotifyURI) -> [Track]? {
        switch uri.kind {
        case .collection:
            return savedTracks
        case .album:
            return MockFixtures.tracks.filter { $0.id.hasPrefix((uri.id ?? "") + "-") }
        default:
            guard let playlist = playlists.first(where: { $0.uri == uri }) else { return nil }
            return MockFixtures.playlistTracks[playlist.id]
        }
    }

    func availableDevices() -> [PlaybackDevice] {
        devices.map { device in
            device.id == activeDeviceID ? activeDevice ?? device : device
        }
    }

    func transfer(to deviceID: String, play: Bool) throws(OrbitError) {
        guard let device = devices.first(where: { $0.id == deviceID }) else { throw .noActiveDevice }
        guard !device.isRestricted else { throw .deviceRestricted }
        activeDeviceID = deviceID
        if let volumePercent = device.volumePercent { volume = volumePercent }
        if play { setPlaying(true) }
        emitChange()
    }

    func queue() -> PlaybackQueue {
        let upcomingContext = contextTracks.isEmpty
            ? []
            : (1...min(5, contextTracks.count)).map { contextTracks[(contextIndex + $0) % contextTracks.count] }
        return PlaybackQueue(current: nowPlaying, upcoming: userQueue + upcomingContext)
    }

    func enqueue(_ uri: SpotifyURI) throws(OrbitError) {
        guard let track = MockFixtures.tracks.first(where: { $0.uri == uri }) else { throw .contentRestricted }
        userQueue.append(track)
    }

    func libraryContains(_ uris: [SpotifyURI]) -> Set<SpotifyURI> {
        Set(uris).intersection(savedTracks.map(\.uri))
    }

    func save(_ uris: [SpotifyURI]) {
        let new = uris.filter { uri in !savedTracks.contains { $0.uri == uri } }
            .compactMap { uri in MockFixtures.tracks.first { $0.uri == uri } }
        savedTracks.insert(contentsOf: new, at: 0)
    }

    func remove(_ uris: [SpotifyURI]) {
        savedTracks.removeAll { uris.contains($0.uri) }
    }

    func savedTracksPage(_ request: PageRequest) -> Page<Track> {
        libraryPage(savedTracks, id: \.id, request)
    }

    private func libraryPage<Item>(_ items: [Item], id: (Item) -> String, _ request: PageRequest) -> Page<Item> {
        var request = request
        if let pageSizeLimit { request.limit = min(request.limit, pageSizeLimit) }
        let raw = Self.page(items, request)
        let kept = raw.items.filter { !droppedFromPages.contains(id($0)) }
        return Page(
            items: kept,
            offset: raw.offset,
            total: raw.total,
            hasMore: raw.hasMore,
            nextOffset: kept.count == raw.items.count ? nil : raw.offset + raw.items.count
        )
    }

    private func start(_ track: Track) {
        nowPlaying = track
        positionAtSample = 0
        sampledAt = now()
        isPlaying = true
    }

    private func restartCurrent() {
        positionAtSample = 0
        sampledAt = now()
    }

    private func advance(wrapping: Bool) {
        if !userQueue.isEmpty {
            start(userQueue.removeFirst())
            return
        }
        guard !contextTracks.isEmpty else { return }
        if shuffle {
            contextIndex = Int.random(in: 0..<contextTracks.count)
        } else if contextIndex + 1 < contextTracks.count {
            contextIndex += 1
        } else if wrapping {
            contextIndex = 0
        } else {
            positionAtSample = nowPlaying?.duration ?? 0
            sampledAt = now()
            isPlaying = false
            return
        }
        start(contextTracks[contextIndex])
    }

    // Without Automation permission the real player only has the notification, which omits volume, shuffle and repeat.
    func emitChange() {
        guard isRunning else { return }
        var state = LocalPlayerState(
            status: nowPlaying == nil ? .stopped : (isPlaying ? .playing : .paused),
            track: nowPlaying,
            position: position
        )
        if automationPermission == .granted {
            if reportsLargerLocalArtwork { state.track = Self.largerArtwork(state.track) }
            state.volume = volume
            state.isShuffling = shuffle
            state.isRepeating = repeatMode != .off
        } else {
            state.track?.artworkURL = nil
        }
        events.send(.stateChanged(state))
    }

    private static func index(of offset: PlayOffset?, in tracks: [Track]) -> Int {
        switch offset {
        case .index(let index): min(max(0, index), tracks.count - 1)
        case .track(let uri): tracks.firstIndex { $0.uri == uri } ?? 0
        case nil: 0
        }
    }

    static func page<Item>(_ items: [Item], _ request: PageRequest) -> Page<Item> {
        let start = min(request.offset, items.count)
        let end = min(start + request.limit, items.count)
        return Page(items: Array(items[start..<end]), offset: start, total: items.count, hasMore: end < items.count)
    }
}
