import Foundation
import OrbitCore
@testable import SpotifyKit
import Testing

struct URLSessionTransportTests {
    // A followed 307 or 308 re-sends the token request's body, the refresh token or the code and verifier, to
    // wherever the Location points; bearer requests must not wander either.
    @Test func redirectsAreReturnedNotFollowed() async throws {
        for status in [301, 302, 303, 307, 308] {
            let elsewhere = CannedHTTPServer(response: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
            let spotify = CannedHTTPServer(
                response: "HTTP/1.1 \(status) Moved\r\nLocation: http://127.0.0.1:\(elsewhere.port)/landed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )
            var refresh = TokenEndpoint.request(.refresh(refreshToken: "secret-refresh"), clientID: "client-123")
            refresh.url = URL(string: "http://127.0.0.1:\(spotify.port)/api/token")
            var api = APIRequest(.get, "/me").urlRequest(token: "secret-access")
            api.url = URL(string: "http://127.0.0.1:\(spotify.port)/v1/me")

            for request in [refresh, api] {
                let (_, response) = try await URLSessionTransport().send(request)
                #expect(response.statusCode == status)
            }
            #expect(spotify.requests.count == 2)
            #expect(elsewhere.requests.isEmpty, "HTTP \(status)")
        }
    }
}
