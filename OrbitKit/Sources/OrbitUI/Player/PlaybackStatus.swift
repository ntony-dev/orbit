import OrbitCore
import OrbitEngine
import SwiftUI

// What Orbit can honestly say about playback, shared by the pill and the player so the two never disagree. Without
// Automation permission Orbit cannot read the desktop app, so "nothing playing" would be a guess; that case asks
// for permission instead.
enum PlaybackStatus: Hashable {
    case playing
    case paused
    case spotifyNotInstalled
    case spotifyClosed
    case automationNeeded
    case automationDenied
    case idle(canBrowse: Bool)

    init(
        hasTrack: Bool,
        isPlaying: Bool,
        isSpotifyInstalled: Bool,
        isSpotifyRunning: Bool,
        automation: AutomationPermission,
        isSignedIn: Bool
    ) {
        if hasTrack {
            self = isPlaying ? .playing : .paused
        } else if !isSpotifyInstalled {
            self = .spotifyNotInstalled
        } else if !isSpotifyRunning {
            self = .spotifyClosed
        } else if automation == .denied {
            self = .automationDenied
        } else if automation == .notDetermined {
            self = .automationNeeded
        } else {
            self = .idle(canBrowse: isSignedIn)
        }
    }

    @MainActor
    init(account: AccountStore, snapshot: PlaybackSnapshot) {
        self.init(
            hasTrack: snapshot.track != nil,
            isPlaying: snapshot.isPlaying,
            isSpotifyInstalled: account.isSpotifyInstalled,
            isSpotifyRunning: account.isSpotifyRunning,
            automation: account.automationPermission,
            isSignedIn: account.authState.isSignedIn
        )
    }

    var hasTrack: Bool { self == .playing || self == .paused }
}

// Spotify's own desktop shortcuts, so the expanded player answers to what Spotify users already know: Space plays
// or pauses, arrows seek, Command-arrows change track and volume.
enum PlayerKeyCommand: Equatable {
    case togglePlayback
    case seek(by: TimeInterval)
    case previousTrack
    case nextTrack
    case changeVolume(by: Int)

    static let seekStep: TimeInterval = 10
    static let volumeStep = 10

    static func command(for key: KeyEquivalent, modifiers: EventModifiers) -> PlayerKeyCommand? {
        // Checked by exclusion because AppKit also flags arrow keys as keypad and function keys.
        guard modifiers.isDisjoint(with: [.shift, .option, .control]) else { return nil }
        let command = modifiers.contains(.command)
        switch key {
        case .space where !command: return .togglePlayback
        case .leftArrow: return command ? .previousTrack : .seek(by: -seekStep)
        case .rightArrow: return command ? .nextTrack : .seek(by: seekStep)
        case .upArrow where command: return .changeVolume(by: volumeStep)
        case .downArrow where command: return .changeVolume(by: -volumeStep)
        default: return nil
        }
    }
}
