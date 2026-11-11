import Foundation
import OrbitCore
import Synchronization

// Seam for OAuth PKCE with the loopback callback on 127.0.0.1:8888. Not implemented yet: sign-in fails with a
// typed error and no session is ever restored.
public actor SpotifyAuthorizer: Authorizer {
    private let clientIDProvider: @Sendable () async -> String?
    private let updates = Broadcaster<AuthState>()
    // Mirrored outside the actor so `stateUpdates()` can start a stream with the current value synchronously.
    private let state = Mutex<AuthState>(.unknown)

    // The provider is asked on every sign-in, so a Client ID entered in settings applies without relaunching.
    public init(clientIDProvider: @escaping @Sendable () async -> String?) {
        self.clientIDProvider = clientIDProvider
    }

    public func currentState() -> AuthState {
        state.withLock { $0 }
    }

    public nonisolated func stateUpdates() -> AsyncStream<AuthState> {
        updates.stream(initial: state.withLock { $0 })
    }

    public func restoreSession() throws(OrbitError) {
        transition(to: .signedOut)
    }

    public func signIn() async throws(OrbitError) {
        guard await clientIDProvider() != nil else { throw .missingClientID }
        throw .notImplemented(feature: "Spotify sign-in")
    }

    public func signOut() {
        transition(to: .signedOut)
    }

    private func transition(to newState: AuthState) {
        state.withLock { $0 = newState }
        updates.send(newState)
    }
}
