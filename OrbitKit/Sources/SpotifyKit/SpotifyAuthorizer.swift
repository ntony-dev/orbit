import AppKit
import Foundation
import OrbitCore
import os
import Synchronization

struct AccessCredential: Hashable, Sendable {
    let token: String
    let sessionID: UUID
}

// Authorization Code with PKCE against a one-shot loopback listener on 127.0.0.1:8888. Tokens live only in the
// login keychain and in this actor's memory.
public actor SpotifyAuthorizer: Authorizer {
    // Refreshing a minute early covers clock skew and requests that are already in flight.
    private static let refreshMargin: TimeInterval = 60
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orbit", category: "SpotifyAuth")

    nonisolated let transport: any HTTPTransport
    nonisolated let now: @Sendable () -> Date
    private let clientIDProvider: @Sendable () async -> String?
    private let tokenStore: any TokenStore
    private let openBrowser: @Sendable (URL) async -> Bool
    private let callbackPort: UInt16
    private let signInTimeout: Duration
    private let updates = Broadcaster<AuthState>()
    // Mirrored outside the actor so `stateUpdates()` can start a stream with the current value synchronously.
    private let state = Mutex<AuthState>(.unknown)

    private var session: StoredSession?
    private var refreshTask: Task<Result<StoredSession, OrbitError>, Never>?
    private var signInTask: Task<Result<Void, OrbitError>, Never>?

    // The provider is asked on every sign-in, so a Client ID entered in settings applies without relaunching.
    public init(clientIDProvider: @escaping @Sendable () async -> String?) {
        self.init(
            clientIDProvider: clientIDProvider,
            tokenStore: KeychainTokenStore(),
            transport: URLSessionTransport(),
            openBrowser: { url in await MainActor.run { NSWorkspace.shared.open(url) } }
        )
    }

    init(
        clientIDProvider: @escaping @Sendable () async -> String?,
        tokenStore: any TokenStore,
        transport: any HTTPTransport,
        openBrowser: @escaping @Sendable (URL) async -> Bool,
        callbackPort: UInt16 = SpotifyAccounts.callbackPort,
        signInTimeout: Duration = .seconds(300),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientIDProvider = clientIDProvider
        self.tokenStore = tokenStore
        self.transport = transport
        self.openBrowser = openBrowser
        self.callbackPort = callbackPort
        self.signInTimeout = signInTimeout
        self.now = now
    }

    public func currentState() -> AuthState {
        state.withLock { $0 }
    }

    public nonisolated func stateUpdates() -> AsyncStream<AuthState> {
        updates.stream(initial: state.withLock { $0 })
    }

    public func restoreSession() async throws(OrbitError) {
        let stored: StoredSession?
        do {
            stored = try tokenStore.load()
        } catch {
            Self.logger.error("Couldn't read the stored Spotify session: \(error.message, privacy: .public)")
            stored = nil
        }
        guard let stored else {
            session = nil
            transition(to: .signedOut)
            return
        }
        // A session granted before Orbit needed a scope would fail on that endpoint forever; ask for a new sign-in.
        guard Set(stored.scopes).isSuperset(of: SpotifyAccounts.scopes) else {
            signOut()
            throw .authExpired
        }
        session = stored
        if needsRefresh(stored) {
            do {
                _ = try await refreshed(stored)
            } catch {
                // Offline at launch is not a reason to sign out: the next request refreshes lazily.
                if error == .authExpired { throw error }
            }
        }
        if session != nil { transition(to: .signedIn) }
    }

    public func signIn() async throws(OrbitError) {
        if let previous = signInTask {
            previous.cancel()
            _ = await previous.value
        }
        let configured = await clientIDProvider()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clientID = configured, !clientID.isEmpty else { throw .missingClientID }

        let task = Task { await self.runSignIn(clientID: clientID) }
        signInTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if signInTask == task { signInTask = nil }
        try result.get()
    }

    public func signOut() {
        signInTask?.cancel()
        signInTask = nil
        refreshTask = nil
        session = nil
        do {
            try tokenStore.delete()
        } catch {
            Self.logger.error("Couldn't delete the stored Spotify session: \(error.message, privacy: .public)")
        }
        transition(to: .signedOut)
    }

    func validCredential() async throws(OrbitError) -> AccessCredential {
        guard let current = session else { throw .notSignedIn }
        let valid = needsRefresh(current) ? try await refreshed(current) : current
        return AccessCredential(token: valid.accessToken, sessionID: valid.id)
    }

    // Called after a 401. When another request already refreshed past `token`, its result is reused.
    func credentialAfterRejection(of token: String) async throws(OrbitError) -> AccessCredential {
        guard let current = session else { throw .notSignedIn }
        guard current.accessToken == token else { return try await validCredential() }
        let refreshed = try await refreshed(current)
        return AccessCredential(token: refreshed.accessToken, sessionID: refreshed.id)
    }

    private func needsRefresh(_ session: StoredSession) -> Bool {
        session.expiresAt.timeIntervalSince(now()) <= Self.refreshMargin
    }

    // Single-flight: concurrent callers share one refresh request.
    private func refreshed(_ stale: StoredSession) async throws(OrbitError) -> StoredSession {
        if let refreshTask { return try await refreshTask.value.get() }
        let task = Task { await self.performRefresh(of: stale) }
        refreshTask = task
        let result = await task.value
        if refreshTask == task { refreshTask = nil }
        return try result.get()
    }

    private func performRefresh(of stale: StoredSession) async -> Result<StoredSession, OrbitError> {
        let result: Result<StoredSession, OrbitError>
        do throws(OrbitError) {
            let request = TokenEndpoint.request(.refresh(refreshToken: stale.refreshToken), clientID: stale.clientID)
            let (data, response) = try await transport.send(request)
            let tokens = try TokenEndpoint.parse(data, response, isRefresh: true, now: now())
            var renewed = stale
            renewed.accessToken = tokens.accessToken
            renewed.refreshToken = tokens.refreshToken ?? stale.refreshToken
            renewed.expiresAt = now().addingTimeInterval(TimeInterval(tokens.expiresIn))
            if let scope = tokens.scope { renewed.scopes = Self.scopes(from: scope) }
            result = .success(renewed)
        } catch {
            result = .failure(error)
        }

        // A sign-out or new sign-in during the request makes this result stale; it must not resurrect a session.
        guard session?.id == stale.id else { return result.flatMap { _ in .failure(.notSignedIn) } }
        switch result {
        case .success(let renewed):
            session = renewed
            do {
                try tokenStore.save(renewed)
            } catch {
                Self.logger.error("Couldn't store the refreshed Spotify session: \(error.message, privacy: .public)")
            }
        case .failure(.authExpired):
            Self.logger.notice("Spotify rejected the refresh token; signing out.")
            session = nil
            try? tokenStore.delete()
            transition(to: .signedOut)
        case .failure:
            break
        }
        return result
    }

    private func runSignIn(clientID: String) async -> Result<Void, OrbitError> {
        let previous = currentState()
        transition(to: .authorizing)
        do throws(OrbitError) {
            let newSession = try await authorize(clientID: clientID)
            // A sign-out or newer sign-in during the token exchange cancels this one; its tokens must not be kept.
            if Task.isCancelled { throw .cancelled }
            try tokenStore.save(newSession)
            refreshTask = nil
            session = newSession
            transition(to: .signedIn)
            return .success(())
        } catch {
            if error != .cancelled {
                Self.logger.error("Spotify sign-in failed: \(error.message, privacy: .public)")
            }
            transition(to: previous == .signedIn && session != nil ? .signedIn : .signedOut)
            return .failure(error)
        }
    }

    private func authorize(clientID: String) async throws(OrbitError) -> StoredSession {
        let pkce = try PKCE.random()
        let expectedState = try SecureRandom.base64URL(byteCount: 32)
        let redirectURI = SpotifyAccounts.redirectURI(port: callbackPort)
        let request = AuthorizationRequest(
            clientID: clientID,
            redirectURI: redirectURI,
            state: expectedState,
            pkce: pkce,
            scopes: SpotifyAccounts.scopes
        )
        let listener = LoopbackCallbackListener(port: callbackPort, path: SpotifyAccounts.callbackPath, timeout: signInTimeout)
        let code = try await listener.receive(
            whenReady: { [openBrowser] () async throws(OrbitError) in
                guard await openBrowser(request.url) else {
                    throw .unexpected(detail: "Orbit couldn't open your browser for sign-in.")
                }
            },
            handle: { components in
                AuthorizationCallback.result(from: components, expectedState: expectedState)
            }
        )
        if Task.isCancelled { throw .cancelled }

        let exchange = TokenEndpoint.request(
            .authorizationCode(code: code, verifier: pkce.verifier, redirectURI: redirectURI),
            clientID: clientID
        )
        let (data, response) = try await transport.send(exchange)
        let tokens = try TokenEndpoint.parse(data, response, isRefresh: false, now: now())
        guard let refreshToken = tokens.refreshToken else {
            throw .unexpected(detail: "Spotify didn't return a refresh token.")
        }
        return StoredSession(
            id: UUID(),
            clientID: clientID,
            accessToken: tokens.accessToken,
            refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(tokens.expiresIn)),
            scopes: Self.scopes(from: tokens.scope ?? SpotifyAccounts.scopes.joined(separator: " "))
        )
    }

    private static func scopes(from value: String) -> [String] {
        value.split(separator: " ").map(String.init)
    }

    private func transition(to newState: AuthState) {
        let changed = state.withLock { current -> Bool in
            guard current != newState else { return false }
            current = newState
            return true
        }
        if changed { updates.send(newState) }
    }
}
