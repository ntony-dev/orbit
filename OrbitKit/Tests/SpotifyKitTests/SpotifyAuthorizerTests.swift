import Foundation
import OrbitCore
@testable import SpotifyKit
import Synchronization
import Testing

@Suite(.serialized)
struct SpotifyAuthorizerTests {
    private func makeAuthorizer(
        clientID: String? = "client-123",
        store: InMemoryTokenStore = InMemoryTokenStore(),
        clock: TestClock = TestClock(),
        transport: StubTransport,
        browser: @escaping @Sendable (URL) async -> Bool = { _ in Issue.record("Browser must not open"); return false },
        port: UInt16 = LocalPorts.free()
    ) -> SpotifyAuthorizer {
        SpotifyAuthorizer(
            clientIDProvider: { clientID },
            tokenStore: store,
            transport: transport,
            openBrowser: browser,
            callbackPort: port,
            signInTimeout: .seconds(10),
            now: { clock.now }
        )
    }

    private static let unusedTransport = StubTransport { _ throws(OrbitError) in
        Issue.record("Unexpected request")
        throw .unexpected(detail: "unexpected request")
    }

    // Plays the browser: reads the authorize URL Orbit built and follows Spotify's redirect back to the listener.
    private static func browser(replyingWith reply: @escaping @Sendable (String) -> String, captured: Locked<URL?>) -> @Sendable (URL) async -> Bool {
        { url in
            captured.set(url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = query.first { $0.name == "state" }?.value ?? ""
            let redirect = query.first { $0.name == "redirect_uri" }?.value ?? ""
            _ = try? await LocalHTTP.get(URL(string: "\(redirect)?\(reply(state))")!)
            return true
        }
    }

    @Test func signInWithoutClientIDFailsBeforeOpeningAnything() async {
        for missing in [nil, "  "] as [String?] {
            let authorizer = makeAuthorizer(clientID: missing, transport: Self.unusedTransport)
            await #expect(throws: OrbitError.missingClientID) { try await authorizer.signIn() }
        }
    }

    @Test func signInRunsTheFullPKCEFlowAndStoresTheSession() async throws {
        let store = InMemoryTokenStore()
        let authorizeURL = Locked<URL?>(nil)
        let transport = StubTransport { request throws(OrbitError) in
            HTTP.response(request, json: HTTP.tokenJSON(access: "access-new", refresh: "refresh-new"))
        }
        let port = LocalPorts.free()
        let authorizer = makeAuthorizer(
            store: store,
            transport: transport,
            browser: Self.browser(replyingWith: { "code=auth-code&state=\($0)" }, captured: authorizeURL),
            port: port
        )
        let updates = authorizer.stateUpdates()

        try await authorizer.signIn()

        #expect(await authorizer.currentState() == .signedIn)
        let session = try #require(store.session)
        #expect(session.accessToken == "access-new")
        #expect(session.refreshToken == "refresh-new")
        #expect(session.clientID == "client-123")

        let exchange = try #require(transport.tokenRequests.first)
        let fields = HTTP.formFields(exchange)
        let challenge = URLComponents(url: try #require(authorizeURL.value), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code_challenge" }?.value
        #expect(fields["code"] == "auth-code")
        #expect(fields["redirect_uri"] == "http://127.0.0.1:\(port)/callback")
        #expect(PKCE.challenge(for: try #require(fields["code_verifier"])) == challenge)

        var states: [AuthState] = []
        for await state in updates {
            states.append(state)
            if state == .signedIn { break }
        }
        #expect(states == [.unknown, .authorizing, .signedIn])
    }

    @Test func forgedCallbackFailsSignInWithoutExchangingACode() async {
        let store = InMemoryTokenStore()
        let authorizer = makeAuthorizer(
            store: store,
            transport: Self.unusedTransport,
            browser: Self.browser(replyingWith: { _ in "code=evil&state=forged" }, captured: Locked(nil))
        )
        await #expect(throws: OrbitError.self) { try await authorizer.signIn() }
        #expect(await authorizer.currentState() == .signedOut)
        #expect(store.session == nil)
    }

    @Test func deniedConsentIsCancellation() async {
        let authorizer = makeAuthorizer(
            transport: Self.unusedTransport,
            browser: Self.browser(replyingWith: { "error=access_denied&state=\($0)" }, captured: Locked(nil))
        )
        await #expect(throws: OrbitError.cancelled) { try await authorizer.signIn() }
        #expect(await authorizer.currentState() == .signedOut)
    }

    @Test func signInCanBeRetriedImmediatelyAfterAFailedCallback() async throws {
        let attempts = Locked(0)
        let transport = StubTransport { request throws(OrbitError) in
            HTTP.response(request, json: HTTP.tokenJSON(access: "access-new", refresh: "refresh-new"))
        }
        let authorizer = makeAuthorizer(transport: transport, browser: Self.browser(replyingWith: { state in
            attempts.increment() == 1 ? "error=access_denied&state=\(state)" : "code=ok&state=\(state)"
        }, captured: Locked(nil)))
        await #expect(throws: OrbitError.cancelled) { try await authorizer.signIn() }
        try await authorizer.signIn()
        #expect(await authorizer.currentState() == .signedIn)
    }

    @Test func busyCallbackPortIsReported() async {
        let occupier = LocalPorts.Occupier()
        let authorizer = makeAuthorizer(transport: Self.unusedTransport, port: occupier.port)
        await #expect(throws: OrbitError.callbackPortInUse(port: Int(occupier.port))) { try await authorizer.signIn() }
        withExtendedLifetime(occupier) {}
    }

    @Test func cancellingSignInStopsWaiting() async {
        let opened = AsyncStream.makeStream(of: Void.self)
        let authorizer = makeAuthorizer(transport: Self.unusedTransport, browser: { _ in
            opened.continuation.yield()
            return true
        })
        let task = Task { try await authorizer.signIn() }
        for await _ in opened.stream { break }
        task.cancel()
        await #expect(throws: OrbitError.cancelled) { try await task.value }
        #expect(await authorizer.currentState() == .signedOut)
    }

    @Test func restoreWithoutStoredSessionSignsOut() async throws {
        let authorizer = makeAuthorizer(transport: Self.unusedTransport)
        #expect(await authorizer.currentState() == .unknown)
        try await authorizer.restoreSession()
        #expect(await authorizer.currentState() == .signedOut)
    }

    @Test func restoreWithValidSessionMakesNoRequest() async throws {
        let clock = TestClock()
        let authorizer = makeAuthorizer(store: InMemoryTokenStore(Sessions.valid(clock: clock)), clock: clock, transport: Self.unusedTransport)
        try await authorizer.restoreSession()
        #expect(await authorizer.currentState() == .signedIn)
        #expect(try await authorizer.validCredential().token == "access-1")
    }

    @Test func restoreRefreshesAnExpiredSessionAndKeepsTheRefreshTokenWhenNotRotated() async throws {
        let clock = TestClock()
        let store = InMemoryTokenStore(Sessions.valid(clock: clock, expiresIn: -10))
        let transport = StubTransport { request throws(OrbitError) in
            HTTP.response(request, json: HTTP.tokenJSON(access: "access-2"))
        }
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: transport)
        try await authorizer.restoreSession()
        #expect(await authorizer.currentState() == .signedIn)
        #expect(store.session?.accessToken == "access-2")
        #expect(store.session?.refreshToken == "refresh-1")
        #expect(HTTP.formFields(try #require(transport.tokenRequests.first))["refresh_token"] == "refresh-1")
    }

    @Test func rejectedRefreshTokenSignsOutAndClearsTheKeychain() async {
        let clock = TestClock()
        let store = InMemoryTokenStore(Sessions.valid(clock: clock, expiresIn: -10))
        let transport = StubTransport { request throws(OrbitError) in
            HTTP.response(request, status: 400, json: #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#)
        }
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: transport)
        await #expect(throws: OrbitError.authExpired) { try await authorizer.restoreSession() }
        #expect(await authorizer.currentState() == .signedOut)
        #expect(store.session == nil)
        await #expect(throws: OrbitError.notSignedIn) { try await authorizer.validCredential() }
    }

    @Test func offlineRestoreStaysSignedInAndRefreshesLater() async throws {
        let clock = TestClock()
        let store = InMemoryTokenStore(Sessions.valid(clock: clock, expiresIn: -10))
        let online = Locked(false)
        let transport = StubTransport { request throws(OrbitError) in
            guard online.value else { throw .network(detail: "offline") }
            return HTTP.response(request, json: HTTP.tokenJSON(access: "access-2", refresh: "refresh-2"))
        }
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: transport)
        try await authorizer.restoreSession()
        #expect(await authorizer.currentState() == .signedIn)
        online.set(true)
        #expect(try await authorizer.validCredential().token == "access-2")
        #expect(store.session?.refreshToken == "refresh-2")
    }

    @Test func sessionMissingANeededScopeAsksForANewSignIn() async {
        let clock = TestClock()
        var session = Sessions.valid(clock: clock)
        session.scopes = ["user-read-playback-state"]
        let store = InMemoryTokenStore(session)
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: Self.unusedTransport)
        await #expect(throws: OrbitError.authExpired) { try await authorizer.restoreSession() }
        #expect(await authorizer.currentState() == .signedOut)
        #expect(store.session == nil)
    }

    @Test func refreshIsSingleFlight() async throws {
        let clock = TestClock()
        let store = InMemoryTokenStore(Sessions.valid(clock: clock))
        let transport = StubTransport { request throws(OrbitError) in
            try? await Task.sleep(for: .milliseconds(100))
            return HTTP.response(request, json: HTTP.tokenJSON(access: "access-2", refresh: "refresh-2"))
        }
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: transport)
        try await authorizer.restoreSession()
        #expect(transport.tokenRequests.isEmpty)
        // Inside the refresh margin, so every caller below needs a new token at the same moment.
        clock.advance(by: 3570)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask { try await authorizer.validCredential().token }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(tokens.count == 20)
        #expect(Set(tokens) == ["access-2"])
        #expect(transport.tokenRequests.count == 1)
    }

    @Test func rejectionRefreshesOnceAndReusesANewerToken() async throws {
        let clock = TestClock()
        let counter = Locked(1)
        let transport = StubTransport { request throws(OrbitError) in
            let next = counter.increment()
            return HTTP.response(request, json: HTTP.tokenJSON(access: "access-\(next)"))
        }
        let authorizer = makeAuthorizer(store: InMemoryTokenStore(Sessions.valid(clock: clock)), clock: clock, transport: transport)
        try await authorizer.restoreSession()
        #expect(try await authorizer.credentialAfterRejection(of: "access-1").token == "access-2")
        // A second request that failed with the old token must not trigger another refresh.
        #expect(try await authorizer.credentialAfterRejection(of: "access-1").token == "access-2")
        #expect(transport.tokenRequests.count == 1)
    }

    @Test func signOutRemovesEverything() async throws {
        let clock = TestClock()
        let store = InMemoryTokenStore(Sessions.valid(clock: clock))
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: Self.unusedTransport)
        try await authorizer.restoreSession()
        await authorizer.signOut()
        #expect(store.session == nil)
        #expect(await authorizer.currentState() == .signedOut)
        await #expect(throws: OrbitError.notSignedIn) { try await authorizer.validCredential() }
    }

    @Test func signOutDuringRefreshDoesNotResurrectTheSession() async throws {
        let clock = TestClock()
        let store = InMemoryTokenStore(Sessions.valid(clock: clock))
        let release = AsyncStream.makeStream(of: Void.self)
        let started = AsyncStream.makeStream(of: Void.self)
        let transport = StubTransport { request throws(OrbitError) in
            started.continuation.yield()
            for await _ in release.stream { break }
            return HTTP.response(request, json: HTTP.tokenJSON(access: "access-2"))
        }
        let authorizer = makeAuthorizer(store: store, clock: clock, transport: transport)
        try await authorizer.restoreSession()
        clock.advance(by: 3600)
        let pending = Task { try await authorizer.validCredential() }
        for await _ in started.stream { break }
        await authorizer.signOut()
        release.continuation.yield()
        _ = try? await pending.value
        #expect(store.session == nil)
        #expect(await authorizer.currentState() == .signedOut)
    }
}
