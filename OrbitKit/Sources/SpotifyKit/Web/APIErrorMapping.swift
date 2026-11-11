import Foundation
import OrbitCore

struct APIErrorBody: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let status: Int?
        let message: String?
        let reason: String?
    }

    let error: Detail?

    static func decode(_ data: Data) -> Detail? {
        (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
    }
}

enum APIErrorMapping {
    // Player reason codes Spotify has long returned for commands the target device refuses. The current reference
    // no longer lists them, so they are matched opportunistically and the endpoint kind is the fallback.
    private static let deviceReasons: Set = ["DEVICE_NOT_CONTROLLABLE", "REMOTE_CONTROL_DISALLOW", "VOLUME_CONTROL_DISALLOW"]
    private static let contentReasons: Set = ["CONTEXT_DISALLOW", "ENDLESS_CONTEXT", "NO_SPECIFIC_TRACK"]

    static func error(status: Int, data: Data, retryAfter: String?, kind: APIRequest.Kind, now: Date) -> OrbitError {
        let detail = APIErrorBody.decode(data)
        let reason = detail?.reason
        let message = detail?.message?.lowercased() ?? ""
        switch status {
        case 401:
            return .authExpired
        case 403:
            return forbidden(reason: reason, message: message, kind: kind)
        case 404:
            return kind == .player || reason == "NO_ACTIVE_DEVICE" ? .noActiveDevice : .notFound
        case 429:
            let wait = RetryAfter.parse(retryAfter, now: now)
            return reason == "QUOTA_EXCEEDED" ? .quotaExceeded(retryAfter: wait) : .rateLimited(retryAfter: wait)
        case 502, 503, 504:
            return .network(detail: "Spotify returned HTTP \(status).")
        default:
            return .unexpected(detail: detail?.message.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)")
        }
    }

    private static func forbidden(reason: String?, message: String, kind: APIRequest.Kind) -> OrbitError {
        if reason == "PREMIUM_REQUIRED" || message.contains("premium required") { return .premiumRequired }
        // Development Mode's wording for accounts missing from the app's allowlist.
        if message.contains("not be registered") || message.contains("not registered") { return .notAllowlisted }
        // Tokens granted before Orbit needed a scope; a fresh sign-in requests the current set.
        if message.contains("insufficient client scope") { return .authExpired }
        if reason == "NO_ACTIVE_DEVICE" { return .noActiveDevice }
        if let reason, deviceReasons.contains(reason) { return .deviceRestricted }
        if let reason, contentReasons.contains(reason) { return .contentRestricted }
        switch kind {
        case .playlistItems: return .playlistItemsUnavailable
        // "Restriction violated" and other unspecific player refusals come from the device declining the command.
        case .player: return .deviceRestricted
        // Read endpoints have no per-item 403s left, so a bare 403 there means the account isn't allowlisted.
        case .other: return .notAllowlisted
        }
    }
}
