import Foundation

public enum RepeatMode: String, CaseIterable, Hashable, Codable, Sendable {
    case off, context, track

    public var next: RepeatMode {
        switch self {
        case .off: .context
        case .context: .track
        case .track: .off
        }
    }
}

// Mirrors the Web API `actions.disallows` keys plus volume, so the UI can disable what the active device refuses.
public enum PlaybackAction: String, CaseIterable, Hashable, Codable, Sendable {
    case pause, resume, seek, skipNext, skipPrevious
    case toggleShuffle, toggleRepeatContext, toggleRepeatTrack
    case transfer, setVolume
}

public struct PlaybackContext: Hashable, Codable, Sendable {
    public var uri: SpotifyURI
    // Spotify does not name contexts in playback state; the engine fills this from the library when it can.
    public var name: String?

    public init(uri: SpotifyURI, name: String? = nil) {
        self.uri = uri
        self.name = name
    }
}

public struct PlaybackDevice: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case computer, smartphone, tablet, speaker, television, automobile, other
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var isActive: Bool
    // Restricted devices accept no Web API commands at all.
    public var isRestricted: Bool
    public var supportsVolume: Bool
    public var volumePercent: Int?

    public init(
        id: String,
        name: String,
        kind: Kind,
        isActive: Bool = false,
        isRestricted: Bool = false,
        supportsVolume: Bool = true,
        volumePercent: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isActive = isActive
        self.isRestricted = isRestricted
        self.supportsVolume = supportsVolume
        self.volumePercent = volumePercent
    }
}

public struct PlaybackSnapshot: Hashable, Codable, Sendable {
    public var track: Track?
    public var isPlaying: Bool
    public var position: TimeInterval
    // When `position` was true, so views can interpolate progress locally instead of polling.
    public var sampledAt: Date
    public var shuffle: Bool
    public var repeatMode: RepeatMode
    public var context: PlaybackContext?
    public var device: PlaybackDevice?
    public var volume: Int?
    public var availableActions: Set<PlaybackAction>

    public init(
        track: Track? = nil,
        isPlaying: Bool = false,
        position: TimeInterval = 0,
        sampledAt: Date = .now,
        shuffle: Bool = false,
        repeatMode: RepeatMode = .off,
        context: PlaybackContext? = nil,
        device: PlaybackDevice? = nil,
        volume: Int? = nil,
        availableActions: Set<PlaybackAction> = []
    ) {
        self.track = track
        self.isPlaying = isPlaying
        self.position = position
        self.sampledAt = sampledAt
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.context = context
        self.device = device
        self.volume = volume
        self.availableActions = availableActions
    }

    public static let idle = PlaybackSnapshot(sampledAt: .distantPast)

    public func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let elapsed = position + max(0, date.timeIntervalSince(sampledAt))
        guard let duration = track?.duration else { return elapsed }
        return min(elapsed, duration)
    }

    public func allows(_ action: PlaybackAction) -> Bool {
        availableActions.contains(action)
    }
}

public struct PlaybackQueue: Hashable, Codable, Sendable {
    public var current: Track?
    public var upcoming: [Track]

    public init(current: Track? = nil, upcoming: [Track] = []) {
        self.current = current
        self.upcoming = upcoming
    }
}

public enum PlayOffset: Hashable, Sendable {
    case index(Int)
    case track(SpotifyURI)
}

public enum PlayTarget: Hashable, Sendable {
    case context(SpotifyURI, offset: PlayOffset? = nil)
    case tracks([SpotifyURI], offset: PlayOffset? = nil)
}
