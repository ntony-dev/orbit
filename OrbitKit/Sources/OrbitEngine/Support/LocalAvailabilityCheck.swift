import OrbitCore

// Whether Spotify is running on this Mac and Orbit may script it. The account store and the coordinator both ask
// at launch and on every expand; overlapping asks share one check, so a second permission query never queues on
// the serial Apple-event channel ahead of the state read that fills the pill.
@MainActor
final class LocalAvailabilityCheck {
    struct Status: Equatable {
        var isRunning: Bool
        // `.requiresSpotifyRunning` whenever the app is not running.
        var permission: AutomationPermission
    }

    private let localPlayer: any LocalPlayer
    private var inFlight: Task<Status, Never>?

    init(localPlayer: any LocalPlayer) {
        self.localPlayer = localPlayer
    }

    func run() async -> Status {
        if let inFlight { return await inFlight.value }
        let task = Task { [localPlayer] in
            let running = await localPlayer.isRunning()
            let permission = running ? await localPlayer.automationPermission(prompting: false) : .requiresSpotifyRunning
            return Status(isRunning: running, permission: permission)
        }
        inFlight = task
        let status = await task.value
        if inFlight == task { inFlight = nil }
        return status
    }
}
