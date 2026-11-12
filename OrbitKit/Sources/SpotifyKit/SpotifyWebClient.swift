import Foundation
import OrbitCore
import os

// The Web API surface that still exists for Development Mode apps after the February 2026 migration.
public actor SpotifyWebClient: SpotifyAPI {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Orbit", category: "SpotifyWebAPI")
    // Spotify's rate limit is a rolling 30 s window; quota exhaustion names no window, so it backs off longer.
    private static let defaultRateLimitWait: TimeInterval = 30
    private static let defaultQuotaWait: TimeInterval = 120
    private static let libraryBatchSize = 40
    private static let likedSongsFallbackSize = 100

    private struct Response {
        let status: Int
        let data: Data
        let headers: HTTPURLResponse
        let sessionID: UUID
    }

    private struct Cooldown {
        let until: Date
        let isQuota: Bool
    }

    private let authorizer: SpotifyAuthorizer
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    // The quota is shared by every Development Mode app on the developer account, so while Spotify is refusing
    // requests nothing is sent: callers get the remaining wait immediately.
    private var cooldown: Cooldown?
    private var cachedUser: (sessionID: UUID, profile: UserProfile)?
    private var likedSongsContextRejected = false

    public init(authorizer: SpotifyAuthorizer) {
        self.init(authorizer: authorizer, transport: authorizer.transport, now: authorizer.now)
    }

    init(authorizer: SpotifyAuthorizer, transport: any HTTPTransport, now: @escaping @Sendable () -> Date) {
        self.authorizer = authorizer
        self.transport = transport
        self.now = now
    }

    public func currentUser() async throws(OrbitError) -> UserProfile {
        let response = try await send(APIRequest(.get, "/me"))
        guard let profile = try APIDecoding.decode(UserDTO.self, from: response.data).profile else {
            throw .unexpected(detail: "Spotify returned a profile without an ID.")
        }
        cachedUser = (response.sessionID, profile)
        return profile
    }

    public func playlists(_ page: PageRequest) async throws(OrbitError) -> Page<Playlist> {
        let userID = try await currentUserID()
        let response = try await send(APIRequest(.get, "/me/playlists", query: Self.paging(page, maximum: 50)))
        return try APIDecoding.decode(PagingDTO<PlaylistDTO>.self, from: response.data)
            .page(requested: page) { $0.playlist(currentUserID: userID) }
    }

    public func playlistItems(playlistID: String, page: PageRequest) async throws(OrbitError) -> Page<Track> {
        guard let segment = APIRequest.pathSegment(playlistID) else { throw .notFound }
        let request = APIRequest(
            .get,
            "/playlists/\(segment)/items",
            query: Self.paging(page, maximum: 50) + [("additional_types", "track,episode")],
            kind: .playlistItems
        )
        return try APIDecoding.decode(PagingDTO<PlaylistEntryDTO>.self, from: try await send(request).data)
            .page(requested: page) { $0.isLocal == true ? nil : $0.playable?.track }
    }

    public func savedTracks(_ page: PageRequest) async throws(OrbitError) -> Page<Track> {
        let response = try await send(APIRequest(.get, "/me/tracks", query: Self.paging(page, maximum: 50)))
        return try APIDecoding.decode(PagingDTO<SavedTrackDTO>.self, from: response.data)
            .page(requested: page) { $0.track?.track }
    }

    public func search(_ query: String, categories: Set<SearchCategory>, page: PageRequest) async throws(OrbitError) -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let types = SearchCategory.allCases.filter(categories.contains)
        guard !trimmed.isEmpty, !types.isEmpty else { return SearchResults() }
        let userID = try await currentUserID()
        let request = APIRequest(.get, "/search", query: [
            ("q", trimmed),
            ("type", types.map(\.rawValue).joined(separator: ",")),
            ("limit", String(min(max(page.limit, 1), 10))),
            ("offset", String(min(max(page.offset, 0), 1000))),
        ])
        let dto = try APIDecoding.decode(SearchDTO.self, from: try await send(request).data)
        return SearchResults(
            tracks: dto.tracks?.items?.elements.compactMap(\.track) ?? [],
            albums: dto.albums?.items?.elements.compactMap(\.album) ?? [],
            playlists: dto.playlists?.items?.elements.compactMap { $0.playlist(currentUserID: userID) } ?? []
        )
    }

    public func playbackState() async throws(OrbitError) -> PlaybackSnapshot? {
        let response = try await send(APIRequest(.get, "/me/player", query: [("additional_types", "track,episode")], kind: .player))
        // 204 with no body is how Spotify says no device is playing anything.
        guard response.status != 204, !response.data.isEmpty else { return nil }
        return try APIDecoding.decode(PlaybackStateDTO.self, from: response.data).snapshot(sampledAt: now())
    }

    public func devices() async throws(OrbitError) -> [PlaybackDevice] {
        let response = try await send(APIRequest(.get, "/me/player/devices", kind: .player))
        return try APIDecoding.decode(DevicesDTO.self, from: response.data).devices?.elements.compactMap(\.device) ?? []
    }

    public func transferPlayback(to deviceID: String, play: Bool) async throws(OrbitError) {
        struct Body: Encodable {
            let deviceIds: [String]
            let play: Bool
        }
        try await send(APIRequest(.put, "/me/player", json: Body(deviceIds: [deviceID], play: play), kind: .player))
    }

    public func play(_ target: PlayTarget, deviceID: String?) async throws(OrbitError) {
        if case .context(let uri, let offset) = target, uri.kind == .collection {
            try await playLikedSongs(offset: offset, deviceID: deviceID)
        } else {
            try await send(Self.playRequest(target, deviceID: deviceID))
        }
    }

    public func resume(deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.put, "/me/player/play", query: [("device_id", deviceID)], kind: .player), tolerating: ["ALREADY_PLAYING"])
    }

    public func pause(deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.put, "/me/player/pause", query: [("device_id", deviceID)], kind: .player), tolerating: ["ALREADY_PAUSED"])
    }

    public func skipToNext(deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.post, "/me/player/next", query: [("device_id", deviceID)], kind: .player))
    }

    public func skipToPrevious(deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.post, "/me/player/previous", query: [("device_id", deviceID)], kind: .player))
    }

    public func seek(to position: TimeInterval, deviceID: String?) async throws(OrbitError) {
        let milliseconds = Int((max(0, position) * 1000).rounded())
        try await send(APIRequest(.put, "/me/player/seek", query: [("position_ms", String(milliseconds)), ("device_id", deviceID)], kind: .player))
    }

    public func setVolume(_ percent: Int, deviceID: String?) async throws(OrbitError) {
        let clamped = min(max(percent, 0), 100)
        try await send(APIRequest(.put, "/me/player/volume", query: [("volume_percent", String(clamped)), ("device_id", deviceID)], kind: .player))
    }

    public func setShuffle(_ enabled: Bool, deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.put, "/me/player/shuffle", query: [("state", String(enabled)), ("device_id", deviceID)], kind: .player))
    }

    public func setRepeat(_ mode: RepeatMode, deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.put, "/me/player/repeat", query: [("state", mode.rawValue), ("device_id", deviceID)], kind: .player))
    }

    public func queue() async throws(OrbitError) -> PlaybackQueue {
        let response = try await send(APIRequest(.get, "/me/player/queue", kind: .player))
        guard response.status != 204, !response.data.isEmpty else { return PlaybackQueue() }
        let dto = try APIDecoding.decode(QueueDTO.self, from: response.data)
        return PlaybackQueue(
            current: dto.currentlyPlaying?.value?.track,
            upcoming: dto.queue?.elements.compactMap(\.track) ?? []
        )
    }

    public func addToQueue(_ uri: SpotifyURI, deviceID: String?) async throws(OrbitError) {
        try await send(APIRequest(.post, "/me/player/queue", query: [("uri", uri.rawValue), ("device_id", deviceID)], kind: .player))
    }

    public func libraryContains(_ uris: [SpotifyURI]) async throws(OrbitError) -> Set<SpotifyURI> {
        var saved: Set<SpotifyURI> = []
        for batch in Self.batches(uris) {
            let response = try await send(APIRequest(.get, "/me/library/contains", query: [("uris", Self.joined(batch))]))
            let flags = try APIDecoding.decode([Bool].self, from: response.data)
            guard flags.count == batch.count else {
                throw .unexpected(detail: "Spotify answered a library check for a different number of items.")
            }
            saved.formUnion(zip(batch, flags).filter(\.1).map(\.0))
        }
        return saved
    }

    public func saveToLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        for batch in Self.batches(uris) {
            try await send(APIRequest(.put, "/me/library", query: [("uris", Self.joined(batch))]))
        }
    }

    public func removeFromLibrary(_ uris: [SpotifyURI]) async throws(OrbitError) {
        for batch in Self.batches(uris) {
            try await send(APIRequest(.delete, "/me/library", query: [("uris", Self.joined(batch))]))
        }
    }

    // Spotify's reference lists only albums, artists and playlists as contexts, but its own clients play Liked
    // Songs as `spotify:user:<id>:collection`. That is tried first; if Spotify rejects it as a bad request, the
    // first saved tracks are played as a track list instead, and the rejection is remembered for this session.
    private func playLikedSongs(offset: PlayOffset?, deviceID: String?) async throws(OrbitError) {
        if !likedSongsContextRejected {
            let context = SpotifyURI.likedSongs(userID: try await currentUserID())
            let request = Self.playRequest(.context(context, offset: offset), deviceID: deviceID)
            let response = try await perform(request)
            if (200..<300).contains(response.status) { return }
            // Spotify has answered unsupported contexts with 400; a 404 that isn't about the device is read the same
            // way, so Liked Songs is never reported as deleted.
            let error = mappedError(response, request)
            guard response.status == 400 || error == .notFound else { throw error }
            Self.logger.notice("Spotify rejected Liked Songs as a context; falling back to a track list.")
            likedSongsContextRejected = true
        }

        let start = if case .index(let index) = offset { max(0, index) } else { 0 }
        var uris: [SpotifyURI] = []
        var request: PageRequest? = PageRequest(offset: start, limit: 50)
        while let current = request, uris.count < Self.likedSongsFallbackSize {
            let page = try await savedTracks(current)
            uris += page.items.filter(\.isPlayable).map(\.uri)
            request = page.nextRequest(limit: 50)
        }
        uris = Array(uris.prefix(Self.likedSongsFallbackSize))
        var trackOffset: PlayOffset?
        if case .track(let uri) = offset {
            if uris.contains(uri) {
                trackOffset = .track(uri)
            } else {
                uris = [uri] + uris.prefix(Self.likedSongsFallbackSize - 1)
            }
        }
        guard !uris.isEmpty else { throw .contentRestricted }
        try await send(Self.playRequest(.tracks(uris, offset: trackOffset), deviceID: deviceID))
    }

    private func currentUserID() async throws(OrbitError) -> String {
        let sessionID = try await authorizer.validCredential().sessionID
        if let cachedUser, cachedUser.sessionID == sessionID { return cachedUser.profile.id }
        return try await currentUser().id
    }

    @discardableResult
    private func send(_ request: APIRequest, tolerating reasons: Set<String> = []) async throws(OrbitError) -> Response {
        let response = try await perform(request)
        if (200..<300).contains(response.status) { return response }
        // Idempotent commands that already hold (pausing while paused) are successes, not errors.
        if response.status == 403, let reason = APIErrorBody.decode(response.data)?.reason, reasons.contains(reason) {
            return response
        }
        throw mappedError(response, request)
    }

    // Returns any status except 401, which is refreshed and retried once, and 429, which starts a cooldown.
    private func perform(_ request: APIRequest) async throws(OrbitError) -> Response {
        try checkCooldown()
        var credential = try await authorizer.validCredential()
        var (data, headers) = try await transport.send(request.urlRequest(token: credential.token))
        if headers.statusCode == 401 {
            credential = try await authorizer.credentialAfterRejection(of: credential.token)
            (data, headers) = try await transport.send(request.urlRequest(token: credential.token))
        }
        let response = Response(status: headers.statusCode, data: data, headers: headers, sessionID: credential.sessionID)
        if response.status == 429 {
            let error = mappedError(response, request)
            startCooldown(for: error)
            throw cooldownError() ?? error
        }
        return response
    }

    private func mappedError(_ response: Response, _ request: APIRequest) -> OrbitError {
        let error = APIErrorMapping.error(
            status: response.status,
            data: response.data,
            retryAfter: response.headers.value(forHTTPHeaderField: "Retry-After"),
            kind: request.kind,
            now: now()
        )
        Self.logger.error("\(request.method.rawValue, privacy: .public) \(request.path, privacy: .private) failed with HTTP \(response.status, privacy: .public)")
        return error
    }

    private func startCooldown(for error: OrbitError) {
        let isQuota = if case .quotaExceeded = error { true } else { false }
        let wait = error.retryAfter ?? (isQuota ? Self.defaultQuotaWait : Self.defaultRateLimitWait)
        let until = now().addingTimeInterval(wait)
        if let cooldown, cooldown.until >= until { return }
        cooldown = Cooldown(until: until, isQuota: isQuota)
    }

    private func checkCooldown() throws(OrbitError) {
        if let error = cooldownError() { throw error }
    }

    private func cooldownError() -> OrbitError? {
        guard let cooldown else { return nil }
        let remaining = cooldown.until.timeIntervalSince(now())
        guard remaining > 0 else {
            self.cooldown = nil
            return nil
        }
        return cooldown.isQuota ? .quotaExceeded(retryAfter: remaining) : .rateLimited(retryAfter: remaining)
    }

    private static func playRequest(_ target: PlayTarget, deviceID: String?) -> APIRequest {
        struct Offset: Encodable {
            let position: Int?
            let uri: String?
        }
        struct Body: Encodable {
            let contextUri: String?
            let uris: [String]?
            let offset: Offset?
        }
        func encode(_ offset: PlayOffset?) -> Offset? {
            switch offset {
            case .index(let index): Offset(position: max(0, index), uri: nil)
            case .track(let uri): Offset(position: nil, uri: uri.rawValue)
            case nil: nil
            }
        }
        let body = switch target {
        case .context(let uri, let offset): Body(contextUri: uri.rawValue, uris: nil, offset: encode(offset))
        case .tracks(let uris, let offset): Body(contextUri: nil, uris: uris.map(\.rawValue), offset: encode(offset))
        }
        let kind: APIRequest.Kind = if case .context = target { .playContext } else { .player }
        return APIRequest(.put, "/me/player/play", query: [("device_id", deviceID)], json: body, kind: kind)
    }

    private static func paging(_ page: PageRequest, maximum: Int) -> [(String, String?)] {
        [("limit", String(min(max(page.limit, 1), maximum))), ("offset", String(max(page.offset, 0)))]
    }

    private static func batches(_ uris: [SpotifyURI]) -> [[SpotifyURI]] {
        var seen: Set<SpotifyURI> = []
        let unique = uris.filter { seen.insert($0).inserted }
        return stride(from: 0, to: unique.count, by: libraryBatchSize).map {
            Array(unique[$0..<min($0 + libraryBatchSize, unique.count)])
        }
    }

    private static func joined(_ uris: [SpotifyURI]) -> String {
        uris.map(\.rawValue).joined(separator: ",")
    }
}
