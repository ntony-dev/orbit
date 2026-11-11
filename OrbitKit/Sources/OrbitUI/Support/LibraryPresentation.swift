import AppKit
import OrbitEngine
import OrbitCore

// Liked Songs is presented as a playlist so it can be pinned, appear in recents and be switched to like any
// other context. Its URI is Spotify's collection context for the signed-in user.
enum LikedSongs {
    static let id = "orbit.liked-songs"

    static func playlist(for profile: UserProfile?, count: Int?) -> Playlist? {
        guard let profile else { return nil }
        return Playlist(
            id: id,
            uri: SpotifyURI(rawValue: "spotify:user:\(profile.id):collection"),
            name: "Liked Songs",
            ownerName: "Your library",
            itemCount: count,
            canReadItems: true
        )
    }

    static func contains(_ playlist: Playlist) -> Bool {
        playlist.id == id || playlist.uri.kind == .collection
    }
}

enum Formatting {
    static func time(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }

    static func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count.formatted()) songs"
    }

    static func playlistSubtitle(_ playlist: Playlist) -> String {
        if LikedSongs.contains(playlist) {
            return playlist.itemCount.map(songCount) ?? "Your saved songs"
        }
        return [playlist.ownerName, playlist.itemCount.map(songCount)].compactMap { $0 }.joined(separator: " · ")
    }
}

extension PlaybackDevice.Kind {
    var symbol: String {
        switch self {
        case .computer: "laptopcomputer"
        case .smartphone: "iphone"
        case .tablet: "ipad"
        case .speaker: "hifispeaker"
        case .television: "tv"
        case .automobile: "car"
        case .other: "speaker.wave.2"
        }
    }
}

@MainActor
enum SpotifyApp {
    static let bundleIdentifier = "com.spotify.client"

    // Opening an item is an explicit request to see it in Spotify, so this one action is allowed to bring
    // Spotify forward.
    static func open(_ uri: SpotifyURI) {
        guard let url = URL(string: uri.rawValue) else { return }
        NSWorkspace.shared.open(url)
    }

    // Launches Spotify behind the user's current app so playback can start without a context switch.
    static func launchInBackground() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    static func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension LoadState {
    // The stores drop the previous value when a reload starts; showing the last loaded value until the reload
    // lands keeps revisited screens and refined searches from flashing placeholders.
    func retaining(_ previous: Value?) -> LoadState<Value> {
        switch self {
        case .idle, .loading: previous.map { .loaded($0) } ?? self
        case .loaded, .failed: self
        }
    }
}
