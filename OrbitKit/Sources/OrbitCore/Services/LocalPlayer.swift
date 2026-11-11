import Foundation

public struct LocalPlayerState: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case playing, paused, stopped
    }

    public var status: Status
    public var track: Track?
    // Optional fields are nil when the source did not report them; the distributed notification omits volume, shuffle and repeat.
    public var position: TimeInterval?
    public var volume: Int?
    public var isShuffling: Bool?
    public var isRepeating: Bool?
    // Whether the current context lets shuffle and repeat change; Spotify's dictionary exposes one shared flag.
    public var canShuffle: Bool?
    public var canRepeat: Bool?

    public init(
        status: Status,
        track: Track? = nil,
        position: TimeInterval? = nil,
        volume: Int? = nil,
        isShuffling: Bool? = nil,
        isRepeating: Bool? = nil,
        canShuffle: Bool? = nil,
        canRepeat: Bool? = nil
    ) {
        self.status = status
        self.track = track
        self.position = position
        self.volume = volume
        self.isShuffling = isShuffling
        self.isRepeating = isRepeating
        self.canShuffle = canShuffle
        self.canRepeat = canRepeat
    }
}

public enum LocalPlayerEvent: Hashable, Sendable {
    case stateChanged(LocalPlayerState)
    case launched
    case terminated
}

// The Spotify desktop app's AppleScript surface. Implementations must never send an Apple event while Spotify is not running, because that launches it.
public protocol LocalPlayer: Sendable {
    func isInstalled() async -> Bool
    func isRunning() async -> Bool
    func automationPermission(prompting: Bool) async -> AutomationPermission
    // Each call returns an independent stream; it never needs Automation permission.
    func events() -> AsyncStream<LocalPlayerEvent>

    func state() async throws(OrbitError) -> LocalPlayerState
    func play() async throws(OrbitError)
    func pause() async throws(OrbitError)
    func playPause() async throws(OrbitError)
    func nextTrack() async throws(OrbitError)
    func previousTrack() async throws(OrbitError)
    func play(track: SpotifyURI, inContext context: SpotifyURI?) async throws(OrbitError)
    func setPosition(_ seconds: TimeInterval) async throws(OrbitError)
    func setVolume(_ percent: Int) async throws(OrbitError)
    func setShuffling(_ enabled: Bool) async throws(OrbitError)
    // AppleScript exposes repeat as a boolean only; it cannot express repeat-one.
    func setRepeating(_ enabled: Bool) async throws(OrbitError)
    // The name this Mac's Spotify app appears under in Spotify Connect, used to recognise it in Web API state.
    func connectDeviceName() async -> String?
}

extension LocalPlayer {
    public func connectDeviceName() async -> String? { nil }
}
