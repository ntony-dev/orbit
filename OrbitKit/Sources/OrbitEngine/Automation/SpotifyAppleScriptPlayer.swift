import AppKit
import OrbitCore
import Synchronization
import SystemConfiguration

// Controls the Spotify desktop app through its scripting dictionary using raw Apple events on a background queue.
// State changes arrive through Spotify's distributed notification, so nothing polls while the app is idle.
public struct SpotifyAppleScriptPlayer: LocalPlayer {
    public static let bundleIdentifier = "com.spotify.client"
    static let stateChangedNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    private let channel: AppleEventChannel
    private let cache: AutomationCache
    private let hub = LocalEventHub()

    public init() {
        channel = AppleEventChannel(bundleIdentifier: Self.bundleIdentifier)
        cache = AutomationCache()
    }

    public func isInstalled() async -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    public func isRunning() async -> Bool {
        channel.isRunning()
    }

    public func automationPermission(prompting: Bool) async -> AutomationPermission {
        let permission = await channel.permission(prompting: prompting)
        cache.permission = permission
        return permission
    }

    // Spotify names the desktop app's Connect device after the computer.
    public func connectDeviceName() async -> String? {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
    }

    // Both stores listen, but each notification is observed and enriched once: enriching costs a round trip of
    // Apple events on the serial channel, ahead of whatever the user just asked for.
    public func events() -> AsyncStream<LocalPlayerEvent> {
        hub.events { send in
            let (raw, rawContinuation) = AsyncStream.makeStream(of: SpotifyEventMonitor.Signal.self, bufferingPolicy: .bufferingNewest(8))
            let monitor = SpotifyEventMonitor(bundleIdentifier: Self.bundleIdentifier, continuation: rawContinuation)
            let player = self
            // One consumer keeps events in posting order even when enriching a notification takes a round trip.
            Task {
                for await signal in raw {
                    switch signal {
                    case .launched:
                        player.cache.permission = nil
                        send(.launched)
                    case .terminated:
                        player.cache.reset()
                        send(.terminated)
                    case .stateChanged(let notified):
                        send(.stateChanged(await player.enrich(notified)))
                    }
                }
                withExtendedLifetime(monitor) {}
            }
            Task { @MainActor in monitor.activate() }
        }
    }

    public func state() async throws(OrbitError) -> LocalPlayerState {
        try await requireAccess()
        return try await readState()
    }

    public func play() async throws(OrbitError) { try await command(.play) }
    public func pause() async throws(OrbitError) { try await command(.pause) }
    public func playPause() async throws(OrbitError) { try await command(.playPause) }
    public func nextTrack() async throws(OrbitError) { try await command(.nextTrack) }
    public func previousTrack() async throws(OrbitError) { try await command(.previousTrack) }

    public func play(track: SpotifyURI, inContext context: SpotifyURI?) async throws(OrbitError) {
        try await command(.playTrack(track, context: context))
    }

    public func setPosition(_ seconds: TimeInterval) async throws(OrbitError) { try await command(.setPosition(seconds)) }
    public func setVolume(_ percent: Int) async throws(OrbitError) { try await command(.setVolume(percent)) }
    public func setShuffling(_ enabled: Bool) async throws(OrbitError) { try await command(.setShuffling(enabled)) }
    public func setRepeating(_ enabled: Bool) async throws(OrbitError) { try await command(.setRepeating(enabled)) }

    // Neither call sends Spotify an Apple event or needs a permission: CGWindowList reports a window's owner, layer
    // and bounds without Screen Recording, and hiding goes through NSRunningApplication.
    public func isShowingWindow() async -> Bool {
        guard let pid = channel.runningProcessID() else { return false }
        return await MainActor.run { SpotifyWindows.isShowingWindow(pid: pid) }
    }

    public func hide() async {
        guard let pid = channel.runningProcessID() else { return }
        await MainActor.run { _ = NSRunningApplication(processIdentifier: pid)?.hide() }
    }

    private func command(_ event: SpotifyAppleEvent) async throws(OrbitError) {
        try await requireAccess()
        do {
            _ = try await channel.send(event)
        } catch {
            if error == .automationDenied { cache.permission = .denied }
            throw error
        }
    }

    // A command is a direct user action, so this is the one place a not-yet-asked permission prompts.
    private func requireAccess() async throws(OrbitError) {
        guard channel.isRunning() else { throw .spotifyNotRunning }
        let permission = cache.permission == .granted ? .granted : await automationPermission(prompting: true)
        switch permission {
        case .granted: return
        case .requiresSpotifyRunning: throw .spotifyNotRunning
        case .denied, .notDetermined: throw .automationDenied
        }
    }

    private func readState() async throws(OrbitError) -> LocalPlayerState {
        let cache = cache
        return try await channel.batch { send in
            let app: SpotifyAppProperties
            switch send(.appProperties) {
            case .success(let reply):
                guard let properties = reply.appProperties else { return .failure(.unexpected(detail: "Unreadable Spotify state")) }
                app = properties
            case .failure(let error):
                return .failure(error)
            }
            var track: Track?
            if app.status != .stopped, case .success(let reply) = send(.trackProperty(.id)), let id = reply.string {
                track = cache.track(id: id) ?? Self.readTrack(id: id, send: send).map { cache.store($0) }
            }
            return .success(LocalPlayerState(
                status: app.status,
                track: track,
                position: app.position,
                volume: app.volume,
                isShuffling: app.isShuffling,
                isRepeating: app.isRepeating,
                canShuffle: app.controlsEnabled,
                canRepeat: app.controlsEnabled
            ))
        }
    }

    private static func readTrack(id: String, send: (SpotifyAppleEvent) -> Result<AppleEventReply, OrbitError>) -> Track? {
        func value(_ property: SpotifyAppleEvent.TrackProperty) -> AppleEventReply? {
            try? send(.trackProperty(property)).get()
        }
        let uri = SpotifyURI(rawValue: id)
        let artist = value(.artist)?.string ?? ""
        return Track(
            id: uri.id ?? id,
            uri: uri,
            name: value(.name)?.string ?? "",
            artists: artist.isEmpty ? [] : [artist],
            album: value(.album)?.string ?? "",
            artworkURL: value(.artworkURL)?.string.flatMap(URL.init(string:)),
            // Spotify reports milliseconds here, although its dictionary says seconds.
            duration: TimeInterval(value(.duration)?.integer ?? 0) / 1000
        )
    }

    // Without permission the notification is all there is; with it, one round trip adds volume, shuffle, repeat
    // and artwork, none of which the notification carries.
    private func enrich(_ notified: LocalPlayerState) async -> LocalPlayerState {
        guard cache.permission == .granted, channel.isRunning() else { return notified }
        guard var full = try? await readState() else { return notified }
        if full.track == nil { full.track = notified.track }
        return full
    }
}

enum SpotifyWindows {
    // Spotify also owns small offscreen helper windows; its main window is far larger than this.
    private static let minimumSide: CGFloat = 100

    // Only windows on screen in the current Space count: minimized and hidden windows are not on screen.
    @MainActor
    static func isShowingWindow(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isHidden else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let rect = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rect)
            else { return false }
            return bounds.width >= minimumSide && bounds.height >= minimumSide
        }
    }
}

// Fans one event source out to every subscriber. The source starts with the first subscription and then runs for
// the life of the player, which is the life of the app.
final class LocalEventHub: Sendable {
    private let broadcaster = Broadcaster<LocalPlayerEvent>()
    private let started = Mutex(false)

    func events(startingSource start: (_ send: @escaping @Sendable (LocalPlayerEvent) -> Void) -> Void) -> AsyncStream<LocalPlayerEvent> {
        let stream = broadcaster.stream()
        let isFirst = started.withLock { started in
            defer { started = true }
            return !started
        }
        if isFirst { start { [broadcaster] in broadcaster.send($0) } }
        return stream
    }
}

// Remembers the current track's details so a play/pause notification costs two events instead of seven, and
// caches the permission so routine reads never call into TCC.
final class AutomationCache: Sendable {
    private struct State {
        var track: Track?
        var permission: AutomationPermission?
    }

    private let state = Mutex(State())

    var permission: AutomationPermission? {
        get { state.withLock { $0.permission } }
        set { state.withLock { $0.permission = newValue } }
    }

    func track(id: String) -> Track? {
        state.withLock { $0.track?.uri.rawValue == id ? $0.track : nil }
    }

    func store(_ track: Track) -> Track {
        state.withLock { $0.track = track }
        return track
    }

    func reset() {
        state.withLock { $0 = State() }
    }
}
