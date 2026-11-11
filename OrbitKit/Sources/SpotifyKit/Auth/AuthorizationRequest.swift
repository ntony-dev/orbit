import Foundation
import OrbitCore

enum SpotifyAccounts {
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    static let callbackPath = "/callback"
    static let callbackPort: UInt16 = 8888

    // The smallest set covering SpotifyAPI. Library writes only ever save tracks and albums, which need just
    // user-library-modify; the follow and playlist-modify scopes that /me/library also lists apply to other URI types.
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        // The queue reference lists this alongside user-read-playback-state without saying either suffices.
        "user-read-currently-playing",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-library-modify",
    ]

    static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(callbackPath)"
    }
}

struct AuthorizationRequest: Sendable {
    let clientID: String
    let redirectURI: String
    let state: String
    let pkce: PKCE
    let scopes: [String]

    var url: URL {
        var components = URLComponents(url: SpotifyAccounts.authorizeURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = FormEncoding.encode([
            ("response_type", "code"),
            ("client_id", clientID),
            ("scope", scopes.joined(separator: " ")),
            ("redirect_uri", redirectURI),
            ("state", state),
            ("code_challenge_method", "S256"),
            ("code_challenge", pkce.challenge),
        ])
        return components.url!
    }
}

enum AuthorizationCallback {
    // State is checked before anything else, so a forged or stale callback can neither complete nor fail sign-in
    // with a code or error of its own choosing.
    static func code(from components: URLComponents, expectedState: String) throws(OrbitError) -> String {
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        guard let state = value("state"), state == expectedState else {
            throw .unexpected(detail: "The sign-in response didn't match the request Orbit made.")
        }
        if let error = value("error") {
            if error == "access_denied" { throw .cancelled }
            throw .unexpected(detail: "Spotify sign-in failed (\(error)).")
        }
        guard let code = value("code"), !code.isEmpty else {
            throw .unexpected(detail: "Spotify didn't return an authorization code.")
        }
        return code
    }
}

enum FormEncoding {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    // Encodes everything outside RFC 3986's unreserved set, so values such as "C++" or "a&b" survive both query
    // strings and form bodies.
    static func encode(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
