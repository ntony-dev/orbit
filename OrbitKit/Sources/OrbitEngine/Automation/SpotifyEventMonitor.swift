import AppKit
import OrbitCore

// Observes Spotify's distributed playback notification and workspace launch/terminate notifications. Observers are
// registered on the main run loop because distributed notifications are only delivered to a thread with one.
@MainActor
final class SpotifyEventMonitor {
    enum Signal: Sendable {
        case stateChanged(LocalPlayerState)
        case launched
        case terminated
    }

    private let bundleIdentifier: String
    private let continuation: AsyncStream<Signal>.Continuation
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    nonisolated init(bundleIdentifier: String, continuation: AsyncStream<Signal>.Continuation) {
        self.bundleIdentifier = bundleIdentifier
        self.continuation = continuation
    }

    func activate() {
        guard observers.isEmpty else { return }
        let continuation = continuation
        let bundleIdentifier = bundleIdentifier
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: SpotifyAppleScriptPlayer.stateChangedNotification, object: nil, queue: .main
        ) { notification in
            if let state = SpotifyNotificationPayload.state(from: notification.userInfo ?? [:]) {
                continuation.yield(.stateChanged(state))
            }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, signal) in [
            (NSWorkspace.didLaunchApplicationNotification, Signal.launched),
            (NSWorkspace.didTerminateApplicationNotification, Signal.terminated),
        ] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == bundleIdentifier { continuation.yield(signal) }
            }))
        }
    }

    func invalidate() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}

// The notification's userInfo, confirmed against Spotify 1.2 on macOS. Duration is in milliseconds and the
// position in seconds; volume, shuffle, repeat and artwork are never included.
enum SpotifyNotificationPayload {
    static func state(from info: [AnyHashable: Any]) -> LocalPlayerState? {
        guard let rawState = info["Player State"] as? String else { return nil }
        let status: LocalPlayerState.Status = switch rawState {
        case "Playing": .playing
        case "Paused": .paused
        default: .stopped
        }
        var track: Track?
        if status != .stopped, let id = info["Track ID"] as? String, !id.isEmpty {
            let uri = SpotifyURI(rawValue: id)
            let artist = info["Artist"] as? String ?? ""
            track = Track(
                id: uri.id ?? id,
                uri: uri,
                name: info["Name"] as? String ?? "",
                artists: artist.isEmpty ? [] : [artist],
                album: info["Album"] as? String ?? "",
                duration: ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000
            )
        }
        return LocalPlayerState(
            status: status,
            track: track,
            position: (info["Playback Position"] as? NSNumber)?.doubleValue
        )
    }
}
