import Foundation
import OrbitCore

extension LossyArray<ImageDTO> {
    // Spotify sorts images largest first; the smallest one that still covers a 300 px artwork slot keeps
    // downloads light without looking soft on Retina.
    func preferredImageURL() -> URL? {
        let candidates = elements.filter { $0.url != nil }
        let sized = candidates.filter { ($0.width ?? 0) >= 300 }.min { ($0.width ?? 0) < ($1.width ?? 0) }
        return (sized ?? candidates.first)?.url
    }
}

extension LossyArray<NamedDTO> {
    var names: [String] {
        elements.compactMap(\.name).filter { !$0.isEmpty }
    }
}

extension PlayableDTO {
    // Local files and items without an ID can't be addressed through the Web API, so they are dropped.
    var track: Track? {
        guard isLocal != true, let id, !id.isEmpty, let name else { return nil }
        let isEpisode = type == "episode"
        let fallbackURI = SpotifyURI(isEpisode ? .episode : .track, id: id)
        let showName = show?.name
        return Track(
            id: id,
            uri: uri.map(SpotifyURI.init(rawValue:)) ?? fallbackURI,
            name: name,
            artists: isEpisode ? [showName].compactMap { $0 } : artists?.names ?? [],
            album: (isEpisode ? showName : album?.name) ?? "",
            albumURI: isEpisode ? nil : album.flatMap { album in
                album.uri.map(SpotifyURI.init(rawValue:)) ?? album.id.map { SpotifyURI(.album, id: $0) }
            },
            artworkURL: isEpisode
                ? (images?.preferredImageURL() ?? show?.images?.preferredImageURL())
                : album?.images?.preferredImageURL(),
            duration: TimeInterval(durationMs ?? 0) / 1000,
            isExplicit: explicit ?? false,
            isPlayable: isPlayable ?? (restrictions == nil)
        )
    }
}

extension AlbumDTO {
    var album: Album? {
        guard let id, !id.isEmpty, let name else { return nil }
        return Album(
            id: id,
            uri: uri.map(SpotifyURI.init(rawValue:)),
            name: name,
            artists: artists?.names ?? [],
            artworkURL: images?.preferredImageURL()
        )
    }
}

extension PlaylistDTO {
    // Spotify serves items only for playlists the user owns or collaborates on.
    func playlist(currentUserID: String?) -> Playlist? {
        guard let id, !id.isEmpty, let name else { return nil }
        let ownerID = owner?.id
        let isOwn = ownerID != nil && ownerID == currentUserID
        return Playlist(
            id: id,
            uri: uri.map(SpotifyURI.init(rawValue:)),
            name: name,
            summary: description.flatMap(HTMLText.plain),
            ownerName: owner?.displayName ?? ownerID ?? "",
            artworkURL: images?.preferredImageURL(),
            itemCount: items?.value?.total ?? tracks?.value?.total,
            canReadItems: isOwn || collaborative == true
        )
    }
}

extension UserDTO {
    var profile: UserProfile? {
        guard let id, !id.isEmpty else { return nil }
        return UserProfile(id: id, displayName: displayName, avatarURL: images?.preferredImageURL())
    }
}

extension DeviceDTO {
    var device: PlaybackDevice? {
        guard let id, !id.isEmpty else { return nil }
        return PlaybackDevice(
            id: id,
            name: name ?? "Unknown device",
            kind: Self.kind(type),
            isActive: isActive ?? false,
            isRestricted: isRestricted ?? false,
            supportsVolume: supportsVolume ?? false,
            volumePercent: volumePercent
        )
    }

    private static func kind(_ type: String?) -> PlaybackDevice.Kind {
        switch type?.lowercased() {
        case "computer": .computer
        case "smartphone": .smartphone
        case "tablet": .tablet
        case "speaker", "avr", "audiodongle", "castaudio": .speaker
        case "tv", "castvideo", "stb": .television
        case "automobile": .automobile
        default: .other
        }
    }
}

extension PlaybackStateDTO {
    private static let actionKeys: [String: PlaybackAction] = [
        "pausing": .pause,
        "resuming": .resume,
        "seeking": .seek,
        "skippingNext": .skipNext,
        "skippingPrev": .skipPrevious,
        "togglingShuffle": .toggleShuffle,
        "togglingRepeatContext": .toggleRepeatContext,
        "togglingRepeatTrack": .toggleRepeatTrack,
        "transferringPlayback": .transfer,
    ]

    func snapshot(sampledAt: Date) -> PlaybackSnapshot {
        let device = device?.device
        var allowed = Set(PlaybackAction.allCases)
        for key in actions?.value?.disallowed ?? [] {
            if let action = Self.actionKeys[key] { allowed.remove(action) }
        }
        if device?.supportsVolume != true { allowed.remove(.setVolume) }
        if device?.isRestricted == true { allowed.removeAll() }
        return PlaybackSnapshot(
            track: item?.value?.track,
            isPlaying: isPlaying ?? false,
            position: TimeInterval(progressMs ?? 0) / 1000,
            sampledAt: sampledAt,
            shuffle: shuffleState ?? false,
            repeatMode: repeatState.flatMap(RepeatMode.init(rawValue:)) ?? .off,
            context: context?.uri.map { PlaybackContext(uri: SpotifyURI(rawValue: $0)) },
            device: device,
            volume: device?.volumePercent,
            availableActions: allowed
        )
    }
}

extension PagingDTO {
    func page<Mapped>(requested: PageRequest, transform: (Item) -> Mapped?) -> Page<Mapped> {
        let rawCount = items?.rawCount ?? 0
        let mapped = items?.elements.compactMap(transform) ?? []
        let start = offset ?? requested.offset
        // An empty page that still claims a `next` would page forever.
        let hasMore = next != nil && rawCount > 0
        return Page(
            items: mapped,
            offset: start,
            total: total,
            hasMore: hasMore,
            nextOffset: mapped.count == rawCount ? nil : start + rawCount
        )
    }
}

enum HTMLText {
    // `&amp;` goes last so an escaped entity such as `&amp;lt;` is not decoded twice.
    private static let entities = [
        ("&quot;", "\""), ("&#x27;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&#x2F;", "/"), ("&amp;", "&"),
    ]

    // Playlist descriptions arrive HTML-escaped and may carry links; the UI shows them as plain text.
    static func plain(_ html: String) -> String? {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
