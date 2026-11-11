import CryptoKit
import Foundation
import OrbitCore
import Security

struct PKCE: Hashable, Sendable {
    let verifier: String
    let challenge: String

    init(verifier: String) {
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
    }

    // 64 random bytes encode to 86 characters, inside RFC 7636's 43...128 range and its unreserved alphabet.
    static func random() throws(OrbitError) -> PKCE {
        PKCE(verifier: try SecureRandom.base64URL(byteCount: 64))
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

enum SecureRandom {
    static func base64URL(byteCount: Int) throws(OrbitError) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw .unexpected(detail: "The system random number generator failed.")
        }
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
