import Foundation
import OrbitCore

// Wire shapes for the Web API. Every field is optional and arrays are lossy, because the February 2026 migration
// removed fields and real responses contain null entries (unavailable tracks, deleted playlists in search).

struct Lossy<Wrapped: Decodable & Sendable>: Decodable, Sendable {
    let value: Wrapped?

    init(from decoder: any Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
    let elements: [Element]
    // Entries as Spotify sent them, including ones that were null or unreadable, for paging arithmetic.
    let rawCount: Int

    init(from decoder: any Decoder) throws {
        guard let decoded = try? [Lossy<Element>](from: decoder) else {
            elements = []
            rawCount = 0
            return
        }
        elements = decoded.compactMap(\.value)
        rawCount = decoded.count
    }
}

struct ImageDTO: Decodable, Sendable {
    let url: URL?
    let width: Int?
}

struct NamedDTO: Decodable, Sendable {
    let name: String?
}

struct AlbumDTO: Decodable, Sendable {
    let id: String?
    let uri: String?
    let name: String?
    let artists: LossyArray<NamedDTO>?
    let images: LossyArray<ImageDTO>?
}

struct ShowDTO: Decodable, Sendable {
    let name: String?
    let images: LossyArray<ImageDTO>?
}

struct RestrictionsDTO: Decodable, Sendable {
    let reason: String?
}

// A TrackObject or EpisodeObject, told apart by `type`.
struct PlayableDTO: Decodable, Sendable {
    let type: String?
    let id: String?
    let uri: String?
    let name: String?
    let durationMs: Int?
    let explicit: Bool?
    let isPlayable: Bool?
    let isLocal: Bool?
    let restrictions: RestrictionsDTO?
    let album: AlbumDTO?
    let artists: LossyArray<NamedDTO>?
    let show: ShowDTO?
    let images: LossyArray<ImageDTO>?
}

struct PagingDTO<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: LossyArray<Item>?
    let offset: Int?
    let total: Int?
    let next: String?
}

struct SavedTrackDTO: Decodable, Sendable {
    let track: PlayableDTO?
}

struct PlaylistEntryDTO: Decodable, Sendable {
    // `item` replaced `track` in 2026; `track` is still sent as a deprecated duplicate and read as a fallback.
    let item: Lossy<PlayableDTO>?
    let track: Lossy<PlayableDTO>?
    let isLocal: Bool?

    var playable: PlayableDTO? { item?.value ?? track?.value }
}

struct CountDTO: Decodable, Sendable {
    let total: Int?
}

struct OwnerDTO: Decodable, Sendable {
    let id: String?
    let displayName: String?
}

struct PlaylistDTO: Decodable, Sendable {
    let id: String?
    let uri: String?
    let name: String?
    let description: String?
    let collaborative: Bool?
    let owner: OwnerDTO?
    let images: LossyArray<ImageDTO>?
    // `items` replaced `tracks` as the count object; absent for playlists the user cannot read.
    let items: Lossy<CountDTO>?
    let tracks: Lossy<CountDTO>?
}

struct UserDTO: Decodable, Sendable {
    let id: String?
    let displayName: String?
    let images: LossyArray<ImageDTO>?
}

struct SearchDTO: Decodable, Sendable {
    let tracks: PagingDTO<PlayableDTO>?
    let albums: PagingDTO<AlbumDTO>?
    let playlists: PagingDTO<PlaylistDTO>?
}

struct DeviceDTO: Decodable, Sendable {
    let id: String?
    let isActive: Bool?
    let isRestricted: Bool?
    let name: String?
    let type: String?
    let volumePercent: Int?
    let supportsVolume: Bool?
}

struct DevicesDTO: Decodable, Sendable {
    let devices: LossyArray<DeviceDTO>?
}

struct ContextDTO: Decodable, Sendable {
    let uri: String?
}

// Spotify has sent these flags both nested under `disallows` and directly on `actions`; a true flag means the
// action is currently not allowed.
struct ActionsDTO: Decodable, Sendable {
    let disallowed: Set<String>

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var flags = Self.flags(in: container)
        if let nested = try? container.nestedContainer(keyedBy: Key.self, forKey: Key(stringValue: "disallows")) {
            flags.formUnion(Self.flags(in: nested))
        }
        disallowed = flags
    }

    private static func flags(in container: KeyedDecodingContainer<Key>) -> Set<String> {
        Set(container.allKeys.filter { (try? container.decode(Bool.self, forKey: $0)) == true }.map(\.stringValue))
    }
}

struct PlaybackStateDTO: Decodable, Sendable {
    let device: DeviceDTO?
    let repeatState: String?
    let shuffleState: Bool?
    let context: ContextDTO?
    let progressMs: Int?
    let isPlaying: Bool?
    let item: Lossy<PlayableDTO>?
    let actions: Lossy<ActionsDTO>?
}

struct QueueDTO: Decodable, Sendable {
    let currentlyPlaying: Lossy<PlayableDTO>?
    let queue: LossyArray<PlayableDTO>?
}

enum APIDecoding {
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws(OrbitError) -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw .unexpected(detail: "Spotify returned a response Orbit couldn't read.")
        }
    }
}
