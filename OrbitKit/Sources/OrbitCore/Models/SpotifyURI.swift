import Foundation

public struct SpotifyURI: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public enum Kind: String, Sendable {
        case track, episode, album, artist, playlist, show, user, collection
    }

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(_ kind: Kind, id: String) {
        self.rawValue = "spotify:\(kind.rawValue):\(id)"
    }

    private var components: [Substring] {
        rawValue.split(separator: ":")
    }

    // Liked Songs is `spotify:user:<id>:collection`, so the trailing component wins over the second one.
    public var kind: Kind? {
        let parts = components
        guard parts.count >= 3, parts[0] == "spotify" else { return nil }
        if parts.last == "collection" { return .collection }
        return Kind(rawValue: String(parts[1]))
    }

    public var id: String? {
        let parts = components
        guard parts.count >= 3, parts[0] == "spotify", parts.last != "collection" else { return nil }
        return String(parts[parts.count - 1])
    }

    public var description: String { rawValue }
}
