import Foundation
import Observation
import OrbitCore

@MainActor
@Observable
public final class AccountStore {
    public private(set) var authState: AuthState = .unknown
    public private(set) var profile: UserProfile?
    public private(set) var automationPermission: AutomationPermission = .notDetermined
    public private(set) var isSpotifyInstalled = true
    public private(set) var isSpotifyRunning = false
    public private(set) var lastError: OrbitError?

    @ObservationIgnored private let authorizer: any Authorizer
    @ObservationIgnored private let api: any SpotifyAPI
    @ObservationIgnored private let localPlayer: any LocalPlayer
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public init(authorizer: any Authorizer, api: any SpotifyAPI, localPlayer: any LocalPlayer) {
        self.authorizer = authorizer
        self.api = api
        self.localPlayer = localPlayer
    }

    public func start() {
        guard tasks.isEmpty else { return }
        let authUpdates = authorizer.stateUpdates()
        let playerEvents = localPlayer.events()
        tasks.append(Task { [weak self] in
            for await state in authUpdates {
                await self?.apply(state)
            }
        })
        tasks.append(Task { [weak self] in
            for await event in playerEvents {
                switch event {
                case .launched, .terminated: await self?.refreshLocalStatus()
                case .stateChanged: break
                }
            }
        })
        tasks.append(Task { [weak self] in
            await self?.refreshLocalStatus()
            await self?.restoreSession()
        })
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    public func dismissError() {
        lastError = nil
    }

    public func signIn() async {
        do {
            try await authorizer.signIn()
        } catch {
            if error != .cancelled { lastError = error }
        }
    }

    public func signOut() async {
        await authorizer.signOut()
    }

    public func refreshLocalStatus() async {
        isSpotifyInstalled = await localPlayer.isInstalled()
        isSpotifyRunning = await localPlayer.isRunning()
        automationPermission = await localPlayer.automationPermission(prompting: false)
    }

    public func requestAutomationPermission() async {
        automationPermission = await localPlayer.automationPermission(prompting: true)
    }

    private func restoreSession() async {
        do {
            try await authorizer.restoreSession()
        } catch {
            lastError = error
        }
    }

    private func apply(_ state: AuthState) async {
        authState = state
        guard state == .signedIn else {
            profile = nil
            return
        }
        do {
            profile = try await api.currentUser()
        } catch {
            lastError = error
        }
    }
}
