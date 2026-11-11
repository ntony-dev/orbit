public protocol Authorizer: Sendable {
    func currentState() async -> AuthState
    // Yields the current state first, then every change.
    func stateUpdates() -> AsyncStream<AuthState>
    // Loads stored credentials; throws `.authExpired` when they can no longer be refreshed.
    func restoreSession() async throws(OrbitError)
    func signIn() async throws(OrbitError)
    func signOut() async
}
