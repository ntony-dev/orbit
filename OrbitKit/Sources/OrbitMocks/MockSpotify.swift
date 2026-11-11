import Foundation
import OrbitCore

// One simulated Spotify behind both the mock local player and the mock Web API, so commands sent through either
// show up in the other, as they do with the real desktop app and Spotify Connect.
public actor MockSpotify {
    private let latency: Duration
    private let now: @Sendable () -> Date
    private let events = Broadcaster<LocalPlayerEvent>()
    private var clockTask: Task<Void, Never>?

    private var isRunning = true
    private var automationPermission = AutomationPermission.granted
    private var savedTracks: [Track]
    private var devices = MockFixtures.devices
    private var activeDeviceID: String? = MockFixtures.devices.first { $0.isActive }?.id

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

    public init(latency: Duration = .milliseconds(120), now: @escaping @Sendable () -> Date = { .now }) {
        self.latency = latency
        self.now = now
        sampledAt = now()
        savedTracks = MockFixtures.savedTrackIDs.compactMap(MockFixtures.track(id:))
        userQueue = MockFixtures.queuedTrackIDs.compactMap(MockFixtures.track(id:))
        let first = MockFixtures.playlists[0]
        context = PlaybackContext(uri: first.uri, name: first.name)
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

    public func stopClock() {
        clockTask?.cancel()
        clockTask = nil
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

    public func simulateQuit() {
        isRunning = false
        isPlaying = false
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

    nonisolated func eventStream() -> AsyncStream<LocalPlayerEvent> {
        events.stream()
    }

    func simulateLatency() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }

    var running: Bool { isRunning }

    func permission(prompting: Bool) -> AutomationPermission {
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

    func localState() throws(OrbitError) -> LocalPlayerState {
        try requireRunning()
        return LocalPlayerState(
            status: nowPlaying == nil ? .stopped : (isPlaying ? .playing : .paused),
            track: nowPlaying,
            position: position,
            volume: volume,
            isShuffling: shuffle,
            isRepeating: repeatMode != .off
        )
    }

    func snapshot() -> PlaybackSnapshot? {
        guard isRunning, let device = activeDevice, nowPlaying != nil else { return nil }
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
        guard isRunning, let device = activeDevice else { throw .noActiveDevice }
        guard !device.isRestricted else { throw .deviceRestricted }
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

    func play(_ target: PlayTarget) throws(OrbitError) {
        switch target {
        case .context(let uri, let offset):
            guard let playlist = MockFixtures.playlists.first(where: { $0.uri == uri }),
                  let tracks = MockFixtures.playlistTracks[playlist.id], !tracks.isEmpty
            else { throw .contentRestricted }
            context = PlaybackContext(uri: uri, name: playlist.name)
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

    func play(track uri: SpotifyURI, inContext contextURI: SpotifyURI?) throws(OrbitError) {
        if let contextURI {
            try play(.context(contextURI, offset: .track(uri)))
        } else {
            try play(.tracks([uri]))
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
        Self.page(savedTracks, request)
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

    private func emitChange() {
        guard let state = try? localState() else { return }
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
