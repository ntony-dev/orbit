import Foundation
import OrbitCore

struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int
    // Spotify may or may not rotate the refresh token on refresh; absent means keep the current one.
    let refreshToken: String?
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

enum TokenEndpoint {
    enum Grant {
        case authorizationCode(code: String, verifier: String, redirectURI: String)
        case refresh(refreshToken: String)
    }

    static func request(_ grant: Grant, clientID: String) -> URLRequest {
        let fields: [(String, String)] = switch grant {
        case .authorizationCode(let code, let verifier, let redirectURI):
            [
                ("grant_type", "authorization_code"),
                ("code", code),
                ("redirect_uri", redirectURI),
                ("client_id", clientID),
                ("code_verifier", verifier),
            ]
        case .refresh(let refreshToken):
            [
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
                ("client_id", clientID),
            ]
        }
        var request = URLRequest(url: SpotifyAccounts.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(FormEncoding.encode(fields).utf8)
        return request
    }

    static func parse(_ data: Data, _ response: HTTPURLResponse, isRefresh: Bool, now: Date) throws(OrbitError) -> TokenResponse {
        let status = response.statusCode
        if (200..<300).contains(status) {
            guard let tokens = try? JSONDecoder().decode(TokenResponse.self, from: data), !tokens.accessToken.isEmpty else {
                throw .unexpected(detail: "Spotify returned an unreadable token response.")
            }
            return tokens
        }
        if status == 429 {
            throw .rateLimited(retryAfter: RetryAfter.parse(response.value(forHTTPHeaderField: "Retry-After"), now: now))
        }
        if status >= 500 {
            throw .network(detail: "Spotify's sign-in service returned HTTP \(status).")
        }
        let code = (try? JSONDecoder().decode(OAuthError.self, from: data))?.error
        // A revoked or expired refresh token (invalid_grant) or a deleted Client ID (invalid_client) can only be
        // fixed by signing in again.
        if isRefresh, code == "invalid_grant" || code == "invalid_client" || status == 401 { throw .authExpired }
        throw .unexpected(detail: "Spotify rejected the token request (\(code ?? "HTTP \(status)")).")
    }

    private struct OAuthError: Decodable {
        let error: String
    }
}
