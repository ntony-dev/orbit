import Foundation
import OrbitCore
import Security

struct StoredSession: Codable, Hashable, Sendable {
    // Identifies one sign-in, so caches keyed to an account can tell when the account behind the tokens changed.
    var id: UUID
    // The Client ID the tokens were issued to; refresh must use it even if the configured ID changes later.
    var clientID: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]
}

extension StoredSession: CustomStringConvertible, CustomDebugStringConvertible {
    // Keeps tokens out of anything that interpolates or dumps a session.
    var description: String { "StoredSession(id: \(id), expiresAt: \(expiresAt), scopes: \(scopes))" }
    var debugDescription: String { description }
}

protocol TokenStore: Sendable {
    func load() throws(OrbitError) -> StoredSession?
    func save(_ session: StoredSession) throws(OrbitError)
    func delete() throws(OrbitError)
}

// Uses the login keychain explicitly: the data-protection keychain needs a provisioned entitlement that ad-hoc
// signed builds don't have.
struct KeychainTokenStore: TokenStore {
    let service: String
    let account = "spotify-session"

    init(service: String = (Bundle.main.bundleIdentifier ?? "orbit") + ".spotify") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    func load() throws(OrbitError) -> StoredSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Self.failure(status) }
        guard let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            // An unreadable item can never be used again; dropping it lets the next sign-in start clean.
            try? delete()
            return nil
        }
        return session
    }

    func save(_ session: StoredSession) throws(OrbitError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(session)
        } catch {
            throw .unexpected(detail: "Couldn't encode the Spotify session.")
        }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Self.failure(update) }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Orbit Spotify session"
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw Self.failure(add) }
    }

    func delete() throws(OrbitError) {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.failure(status) }
    }

    private static func failure(_ status: OSStatus) -> OrbitError {
        .unexpected(detail: "Keychain error \(status).")
    }
}
