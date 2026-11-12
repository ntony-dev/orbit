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

    // Clicking the pill opens the screen that can act on what it says: the library only when nothing plays and a
    // playlist can be started from it, otherwise the player, where the Allow, Open Spotify and transport controls
    // live.
    var pillDestination: PanelDestination {
        if case .idle(canBrowse: true) = self { return .playlistPicker }
        return .player
    }
}
