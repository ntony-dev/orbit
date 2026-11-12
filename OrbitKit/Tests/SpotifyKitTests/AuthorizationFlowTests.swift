import Foundation
import OrbitCore
@testable import SpotifyKit
import Testing

struct PKCETests {
    @Test func challengeMatchesRFC7636AppendixB() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomVerifierIsLongUnreservedAndUnique() throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let first = try PKCE.random()
        let second = try PKCE.random()
        #expect((43...128).contains(first.verifier.count))
        #expect(first.verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(first.verifier != second.verifier)
        #expect(first.challenge == PKCE.challenge(for: first.verifier))
    }
}

struct AuthorizationRequestTests {
    @Test func urlCarriesEveryPKCEParameterAndNoSecret() throws {
        let request = AuthorizationRequest(
            clientID: "client-123",
            redirectURI: SpotifyAccounts.redirectURI(port: SpotifyAccounts.callbackPort),
            state: "state-abc",
            pkce: PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            scopes: SpotifyAccounts.scopes
        )
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.host == "accounts.spotify.com")
        #expect(components.path == "/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "client-123")
        #expect(query["redirect_uri"] == "http://127.0.0.1:8888/callback")
        #expect(query["state"] == "state-abc")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(query["scope"]?.split(separator: " ").map(String.init) == SpotifyAccounts.scopes)
        #expect(query["client_secret"] == nil)
        #expect(components.percentEncodedQuery?.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A8888%2Fcallback") == true)
    }

    @Test func scopesAreTheMinimumForTheAPI() {
        #expect(Set(SpotifyAccounts.scopes) == [
            "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
            "playlist-read-private", "playlist-read-collaborative", "user-library-read", "user-library-modify",
        ])
    }
}

struct AuthorizationCallbackTests {
    private func result(_ query: String) -> Result<String, OrbitError>? {
        AuthorizationCallback.result(from: URLComponents(string: "http://127.0.0.1:8888/callback?\(query)")!, expectedState: "s1")
    }

    @Test func returnsCodeWhenStateMatches() {
        #expect(result("code=abc123&state=s1") == .success("abc123"))
    }

    @Test func callbacksWithoutTheExpectedStateAreNotForThisSignIn() {
        #expect(result("code=abc&state=forged") == nil)
        #expect(result("code=abc") == nil)
        #expect(result("code=abc&state=") == nil)
        #expect(result("code=abc&state=S1") == nil)
        #expect(result("error=access_denied&state=forged") == nil)
        #expect(result("error=server_error") == nil)
        #expect(result("state=forged&state=s1&code=abc") == nil)
    }

    @Test func userDenialIsCancellation() {
        #expect(result("error=access_denied&state=s1") == .failure(.cancelled))
    }

    @Test func otherErrorsAndMissingCodeFail() {
        #expect(result("error=server_error&state=s1") == .failure(.unexpected(detail: "Spotify sign-in failed (server_error).")))
        #expect(result("state=s1") == .failure(.unexpected(detail: "Spotify didn't return an authorization code.")))
        #expect(result("code=&state=s1") == .failure(.unexpected(detail: "Spotify didn't return an authorization code.")))
    }
}

struct TokenEndpointTests {
    @Test func codeExchangeIsAFormPostWithVerifierAndNoSecret() {
        let request = TokenEndpoint.request(
            .authorizationCode(code: "the code", verifier: "verifier~1", redirectURI: "http://127.0.0.1:8888/callback"),
            clientID: "client-123"
        )
        #expect(request.url?.absoluteString == "https://accounts.spotify.com/api/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(HTTP.formFields(request) == [
            "grant_type": "authorization_code",
            "code": "the code",
            "redirect_uri": "http://127.0.0.1:8888/callback",
            "client_id": "client-123",
            "code_verifier": "verifier~1",
        ])
    }

    @Test func refreshSendsClientIDAndRefreshToken() {
        let request = TokenEndpoint.request(.refresh(refreshToken: "r+1/="), clientID: "client-123")
        #expect(HTTP.formFields(request) == ["grant_type": "refresh_token", "refresh_token": "r+1/=", "client_id": "client-123"])
        #expect(String(decoding: request.httpBody!, as: UTF8.self).contains("refresh_token=r%2B1%2F%3D"))
    }

    @Test func parsesTokensAndMapsFailures() throws {
        let request = TokenEndpoint.request(.refresh(refreshToken: "r"), clientID: "c")
        let now = Date()
        let (data, ok) = HTTP.response(request, json: HTTP.tokenJSON(access: "a1", refresh: "r2"))
        let tokens = try TokenEndpoint.parse(data, ok, isRefresh: true, now: now)
        #expect(tokens.accessToken == "a1")
        #expect(tokens.refreshToken == "r2")
        #expect(tokens.expiresIn == 3600)

        let (revoked, bad) = HTTP.response(request, status: 400, json: #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#)
        #expect(throws: OrbitError.authExpired) { try TokenEndpoint.parse(revoked, bad, isRefresh: true, now: now) }
        #expect(throws: OrbitError.self) { try TokenEndpoint.parse(revoked, bad, isRefresh: false, now: now) }

        let (limited, tooMany) = HTTP.response(request, status: 429, headers: ["Retry-After": "7"])
        #expect(throws: OrbitError.rateLimited(retryAfter: 7)) { try TokenEndpoint.parse(limited, tooMany, isRefresh: true, now: now) }

        let (down, unavailable) = HTTP.response(request, status: 503)
        #expect(throws: OrbitError.network(detail: "Spotify's sign-in service returned HTTP 503.")) {
            try TokenEndpoint.parse(down, unavailable, isRefresh: true, now: now)
        }
    }

    @Test func sessionDescriptionsNeverContainTokens() {
        let session = Sessions.valid(clock: TestClock(), access: "secret-access", refresh: "secret-refresh")
        #expect(!"\(session)".contains("secret"))
        #expect(!String(reflecting: session).contains("secret"))
    }
}

struct RetryAfterTests {
    @Test func parsesSecondsAndHTTPDates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RetryAfter.parse("12", now: now) == 12)
        #expect(RetryAfter.parse(nil, now: now) == nil)
        #expect(RetryAfter.parse("soon", now: now) == nil)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        #expect(RetryAfter.parse(formatter.string(from: now.addingTimeInterval(90)), now: now) == 90)
    }
}
