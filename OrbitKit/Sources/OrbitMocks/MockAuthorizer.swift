import Foundation
import OrbitCore
import Synchronization

public final class MockAuthorizer: Authorizer {
    private let state: Mutex<AuthState>
    private let updates = Broadcaster<AuthState>()
    private let restoredState: AuthState
    private let latency: Duration

    // `restoredState` is what a stored session restores to, so tests can start signed in or signed out.
    public init(restoredState: AuthState = .signedIn, latency: Duration = .milliseconds(300)) {
        self.restoredState = restoredState
        self.latency = latency
        state = Mutex(.unknown)
    }

    public func currentState() async -> AuthState {
        state.withLock { $0 }
    }

    public func stateUpdates() -> AsyncStream<AuthState> {
        updates.stream(initial: state.withLock { $0 })
    }

    public func restoreSession() async throws(OrbitError) {
        transition(to: restoredState)
    }

    public func signIn() async throws(OrbitError) {
        transition(to: .authorizing)
        if latency > .zero { try? await Task.sleep(for: latency) }
        transition(to: .signedIn)
    }

    public func signOut() async {
        transition(to: .signedOut)
    }

    private func transition(to newState: AuthState) {
        state.withLock { $0 = newState }
        updates.send(newState)
    }
}
