import Foundation
import OrbitCore
@testable import OrbitEngine
import OrbitMocks
import Testing

@MainActor
struct AccountStoreTests {
    let rig = Rig()

    private func account(restoring state: AuthState = .signedIn) -> AccountStore {
        AccountStore(authorizer: MockAuthorizer(restoredState: state, latency: .zero), api: rig.services.api, localPlayer: rig.services.localPlayer)
    }

    @Test func restoredSessionLoadsTheProfile() async {
        let account = account()
        account.start()
        #expect(await eventually { account.profile != nil })
        #expect(account.authState == .signedIn)
        #expect(account.profile == MockFixtures.user)
        #expect(account.automationPermission == .granted)
        #expect(account.isSpotifyRunning)
    }

    @Test func noStoredSessionEndsSignedOut() async {
        let account = account(restoring: .signedOut)
        account.start()
        #expect(await eventually { account.authState == .signedOut })
        #expect(account.profile == nil)
    }

    @Test func signOutClearsTheProfile() async {
        let account = account()
        account.start()
        #expect(await eventually { account.profile != nil })
        await account.signOut()
        #expect(await eventually { account.authState == .signedOut })
        #expect(account.profile == nil)
    }

    @Test func spotifyQuittingAndRelaunchingIsTracked() async {
        let account = account()
        account.start()
        #expect(await eventually { account.isSpotifyRunning })
        await rig.spotify.simulateQuit()
        #expect(await eventually { !account.isSpotifyRunning })
        #expect(account.automationPermission == .requiresSpotifyRunning)
        await rig.spotify.simulateLaunch()
        #expect(await eventually { account.isSpotifyRunning && account.automationPermission == .granted })
    }

    @Test func deniedAutomationIsReported() async {
        await rig.spotify.setAutomationPermission(.denied)
        let account = account()
        await account.refreshLocalStatus()
        #expect(account.automationPermission == .denied)
    }

    @Test func storesWireSignInToTheCoordinatorAndLibrary() async {
        let stores = rig.stores()
        stores.start()
        #expect(await eventually { stores.library.playlists.value != nil && stores.library.devices.value != nil })
        await stores.account.signOut()
        #expect(await eventually { stores.library.playlists == .idle })
        let requests = await rig.spotify.webRequests.count
        await stores.playback.refresh()
        #expect(await rig.spotify.webRequests.count == requests)
        #expect(stores.playback.authority == .local)
    }

    // Both stores need to know whether Spotify runs and may be scripted; one check over the serial channel answers
    // both, at launch and on every expand, ahead of the state read that fills the pill.
    @Test func launchAndEachExpandCheckAutomationOnce() async {
        let stores = rig.stores()
        stores.start()
        #expect(await eventually { stores.account.hasReadLocalStatus && stores.playback.snapshot.track != nil })
        await settle()
        #expect(await rig.spotify.permissionChecks == 1)
        #expect(await rig.spotify.stateReads == 1)
        #expect(stores.account.automationPermission == .granted)
        #expect(stores.account.isSpotifyRunning)

        for _ in 0..<2 {
            stores.setInterfaceVisibility(.expanded)
            await settle()
            stores.setInterfaceVisibility(.collapsed)
            await settle()
        }
        #expect(await rig.spotify.permissionChecks == 3)
    }

    @Test func automationGrantedLaterStillRefreshesPlayback() async {
        await rig.spotify.setAutomationPermission(.denied)
        let stores = rig.stores()
        stores.start()
        #expect(await eventually { stores.account.automationPermission == .denied })
        await settle()
        let reads = await rig.spotify.stateReads
        await rig.spotify.setAutomationPermission(.granted)
        await stores.account.refreshLocalStatus()
        #expect(await eventually { await rig.spotify.stateReads > reads })
    }
}
