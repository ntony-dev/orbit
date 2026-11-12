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
    // False until the first local status read, so the permission's placeholder is never taken for a change.
    private(set) var hasReadLocalStatus = false

    @ObservationIgnored private let authorizer: any Authorizer
    @ObservationIgnored private let api: any SpotifyAPI
    @ObservationIgnored private let localPlayer: any LocalPlayer
    @ObservationIgnored private let availability: LocalAvailabilityCheck
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    public convenience init(authorizer: any Authorizer, api: any SpotifyAPI, localPlayer: any LocalPlayer) {
        self.init(authorizer: authorizer, api: api, localPlayer: localPlayer, availability: LocalAvailabilityCheck(localPlayer: localPlayer))
    }

    init(authorizer: any Authorizer, api: any SpotifyAPI, localPlayer: any LocalPlayer, availability: LocalAvailabilityCheck) {
        self.authorizer = authorizer
        self.api = api
        self.localPlayer = localPlayer
        self.availability = availability
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
        async let installed = localPlayer.isInstalled()
        let status = await availability.run()
        isSpotifyInstalled = await installed
        isSpotifyRunning = status.isRunning
        automationPermission = status.permission
        hasReadLocalStatus = true
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
