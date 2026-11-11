import Foundation
import OrbitCore
@testable import SpotifyKit
import Synchronization
import Testing

// Routes requests by "METHOD /path" to canned responses; token refreshes are answered separately.
private final class Router: Sendable {
    typealias Reply = @Sendable (URLRequest) -> (Data, HTTPURLResponse)

    private let routes = Mutex<[String: [Reply]]>([:])
    let refreshedToken = Mutex("access-2")

    func on(_ key: String, status: Int = 200, json: String = "", headers: [String: String] = [:]) {
        on(key) { HTTP.response($0, status: status, json: json, headers: headers) }
    }

    // Replies queue up per route; the last one repeats.
    func on(_ key: String, reply: @escaping Reply) {
        routes.withLock { $0[key, default: []].append(reply) }
    }

    func handle(_ request: URLRequest) throws(OrbitError) -> (Data, HTTPURLResponse) {
        if request.url == SpotifyAccounts.tokenURL {
            return HTTP.response(request, json: HTTP.tokenJSON(access: refreshedToken.withLock { $0 }))
        }
        let key = "\(request.httpMethod ?? "GET") \(request.url!.path.replacingOccurrences(of: "/v1", with: ""))"
        let reply = routes.withLock { routes -> Reply? in
            guard var queue = routes[key], !queue.isEmpty else { return nil }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[key] = queue
            return next
        }
        guard let reply else {
            Issue.record("No route for \(key)")
            throw .unexpected(detail: "no route")
        }
        return reply(request)
    }
}

private struct Harness {
    let router = Router()
    let clock = TestClock()
    let transport: StubTransport
    let authorizer: SpotifyAuthorizer
    let client: SpotifyWebClient

    init() async throws {
        let router = router
        let clock = clock
        transport = StubTransport { request throws(OrbitError) in try router.handle(request) }
        authorizer = SpotifyAuthorizer(
            clientIDProvider: { "client-123" },
            tokenStore: InMemoryTokenStore(Sessions.valid(clock: clock)),
            transport: transport,
            openBrowser: { _ in false },
            callbackPort: LocalPorts.free(),
            now: { clock.now }
        )
        try await authorizer.restoreSession()
        client = SpotifyWebClient(authorizer: authorizer, transport: transport, now: { clock.now })
        router.on("GET /me", json: Fixtures.me)
    }

    var apiRequests: [URLRequest] { transport.apiRequests }

    func lastRequest(_ key: String) -> URLRequest? {
        apiRequests.last { "\($0.httpMethod ?? "") \($0.url!.path.replacingOccurrences(of: "/v1", with: ""))" == key }
    }
}

struct WebClientDecodingTests {
    @Test func currentUserMapsProfileAndSendsBearerToken() async throws {
        let harness = try await Harness()
        let user = try await harness.client.currentUser()
        #expect(user == UserProfile(id: "tony", displayName: "Tony", avatarURL: URL(string: "https://i.scdn.co/image/avatar-640")))
        let request = try #require(harness.lastRequest("GET /me"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.url?.absoluteString == "https://api.spotify.com/v1/me")
    }

    @Test func playlistsMapOwnershipCountsAndDescriptions() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/playlists", json: Fixtures.playlists)
        let page = try await harness.client.playlists(PageRequest(offset: 0, limit: 3))

        #expect(page.items.map(\.id) == ["pl-own", "pl-collab", "pl-followed"])
        #expect(page.items.map(\.canReadItems) == [true, true, false])
        #expect(page.items.map(\.itemCount) == [42, 12, nil])
        #expect(page.items[0].summary == "Late & slow mix")
        #expect(page.items[0].ownerName == "Tony")
        #expect(page.items[1].ownerName == "friend")
        #expect(page.items[1].artworkURL == nil)
        #expect(page.items[2].summary == nil)
        #expect(page.items[2].artworkURL == URL(string: "https://i.scdn.co/image/followed"))
        #expect(page.items[0].uri == "spotify:playlist:pl-own")
        #expect(page.total == 7)
        #expect(page.nextRequest(limit: 3) == PageRequest(offset: 3, limit: 3))
        #expect(HTTP.query(try #require(harness.lastRequest("GET /me/playlists"))) == ["limit": "3", "offset": "0"])
    }

    @Test func currentUserIsFetchedOncePerSession() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/playlists", json: Fixtures.playlists)
        _ = try await harness.client.playlists(PageRequest())
        _ = try await harness.client.playlists(PageRequest())
        #expect(harness.apiRequests.filter { $0.url?.path == "/v1/me" }.count == 1)
    }

    @Test func playlistItemsSkipNullAndLocalEntriesWithoutBreakingPaging() async throws {
        let harness = try await Harness()
        harness.router.on("GET /playlists/pl-own/items", json: Fixtures.playlistItems)
        let page = try await harness.client.playlistItems(playlistID: "pl-own", page: PageRequest(offset: 0, limit: 5))

        #expect(page.items.map(\.id) == ["trk1", "ep1", "trk2"])
        let track = page.items[0]
        #expect(track.name == "Night Drive")
        #expect(track.artists == ["Nova", "Echo"])
        #expect(track.album == "Blue Hours")
        #expect(track.artworkURL == URL(string: "https://i.scdn.co/image/alb1-300"))
        #expect(track.duration == 215)
        #expect(track.isExplicit)
        #expect(track.isPlayable)

        let episode = page.items[1]
        #expect(episode.uri == "spotify:episode:ep1")
        #expect(episode.artists == ["The Show"])
        #expect(episode.artworkURL == URL(string: "https://i.scdn.co/image/ep1"))
        #expect(!page.items[2].isPlayable)

        // Five raw entries were consumed even though three survived, so the next page starts at 5, not 3.
        #expect(page.nextRequest(limit: 5) == PageRequest(offset: 5, limit: 5))
        let query = HTTP.query(try #require(harness.lastRequest("GET /playlists/pl-own/items")))
        #expect(query == ["limit": "5", "offset": "0", "additional_types": "track,episode"])
    }

    @Test func savedTracksAndClampedPaging() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/tracks", json: Fixtures.savedTracks)
        let page = try await harness.client.savedTracks(PageRequest(offset: -4, limit: 500))
        #expect(page.items.map(\.id) == ["trk1", "trk2"])
        #expect(!page.hasMore)
        #expect(page.nextRequest(limit: 50) == nil)
        #expect(HTTP.query(try #require(harness.lastRequest("GET /me/tracks"))) == ["limit": "50", "offset": "0"])
    }

    @Test func searchCapsLimitAndDropsNullResults() async throws {
        let harness = try await Harness()
        harness.router.on("GET /search", json: Fixtures.search)
        let results = try await harness.client.search(" nova c++ ", categories: [.playlist, .track, .album], page: PageRequest(offset: 0, limit: 50))
        #expect(results.tracks.map(\.id) == ["trk1"])
        #expect(results.albums.map(\.name) == ["Blue Hours"])
        #expect(results.albums.first?.artists == ["Nova"])
        #expect(results.playlists.map(\.id) == ["pl-search"])
        #expect(results.playlists.first?.canReadItems == false)

        let request = try #require(harness.lastRequest("GET /search"))
        #expect(HTTP.query(request) == ["q": "nova c++", "type": "track,album,playlist", "limit": "10", "offset": "0"])
        #expect(request.url?.query?.contains("q=nova%20c%2B%2B") == true)
    }

    @Test func emptySearchSendsNothing() async throws {
        let harness = try await Harness()
        #expect(try await harness.client.search("   ", categories: [.track], page: PageRequest()).isEmpty)
        #expect(harness.apiRequests.isEmpty)
    }

    @Test func playbackStateMapsDeviceContextAndDisallowedActions() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player", json: Fixtures.playbackState)
        let snapshot = try #require(try await harness.client.playbackState())
        #expect(snapshot.track?.id == "trk1")
        #expect(snapshot.isPlaying)
        #expect(snapshot.position == 61.5)
        #expect(snapshot.sampledAt == harness.clock.now)
        #expect(snapshot.shuffle)
        #expect(snapshot.repeatMode == .context)
        #expect(snapshot.context == PlaybackContext(uri: "spotify:playlist:pl-own"))
        #expect(snapshot.device?.kind == .computer)
        #expect(snapshot.volume == 64)
        #expect(!snapshot.allows(.resume))
        #expect(!snapshot.allows(.skipPrevious))
        #expect(snapshot.allows(.toggleRepeatTrack))
        #expect(snapshot.allows(.pause))
        #expect(snapshot.allows(.setVolume))
        #expect(HTTP.query(try #require(harness.lastRequest("GET /me/player"))) == ["additional_types": "track,episode"])
    }

    @Test func actionsListedDirectlyOnTheActionsObjectAreHonoredToo() throws {
        let json = #"{"is_playing":false,"device":{"id":"d","is_restricted":false,"supports_volume":false},"actions":{"pausing":true,"seeking":false}}"#
        let dto = try APIDecoding.decode(PlaybackStateDTO.self, from: Data(json.utf8))
        let snapshot = dto.snapshot(sampledAt: Date())
        #expect(!snapshot.allows(.pause))
        #expect(snapshot.allows(.seek))
        #expect(!snapshot.allows(.setVolume))
    }

    @Test func nothingPlayingIsNil() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player", status: 204)
        #expect(try await harness.client.playbackState() == nil)
    }

    @Test func devicesDropUnaddressableOnesAndMapKinds() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/devices", json: Fixtures.devices)
        let devices = try await harness.client.devices()
        #expect(devices.map(\.id) == ["dev-mac", "dev-tv", "dev-cast"])
        #expect(devices.map(\.kind) == [.computer, .television, .speaker])
        #expect(devices[1].isRestricted)
        #expect(!devices[1].supportsVolume)
        #expect(devices[2].volumePercent == 30)
    }

    @Test func queueSkipsNullEntries() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/queue", json: Fixtures.queue)
        let queue = try await harness.client.queue()
        #expect(queue.current?.id == "trk1")
        #expect(queue.upcoming.map(\.id) == ["ep1", "trk2"])
    }

    @Test func libraryContainsBatchesByFortyAndMapsFlags() async throws {
        let harness = try await Harness()
        let uris = (0..<45).map { SpotifyURI(.track, id: "t\($0)") }
        harness.router.on("GET /me/library/contains") { request in
            let count = HTTP.query(request)["uris"]!.split(separator: ",").count
            let flags = (0..<count).map { $0 == 0 ? "true" : "false" }.joined(separator: ",")
            return HTTP.response(request, json: "[\(flags)]")
        }
        let saved = try await harness.client.libraryContains(uris + [uris[0]])
        #expect(saved == [uris[0], uris[40]])
        let requests = harness.apiRequests.filter { $0.url?.path == "/v1/me/library/contains" }
        #expect(requests.count == 2)
        #expect(HTTP.query(requests[0])["uris"] == uris.prefix(40).map(\.rawValue).joined(separator: ","))
    }

    @Test func libraryWritesUseURIsInTheQuery() async throws {
        let harness = try await Harness()
        harness.router.on("PUT /me/library")
        harness.router.on("DELETE /me/library")
        try await harness.client.saveToLibrary(["spotify:track:a", "spotify:album:b"])
        try await harness.client.removeFromLibrary(["spotify:track:a"])
        let save = try #require(harness.lastRequest("PUT /me/library"))
        #expect(HTTP.query(save) == ["uris": "spotify:track:a,spotify:album:b"])
        #expect(save.httpBody == Data())
        #expect(HTTP.query(try #require(harness.lastRequest("DELETE /me/library"))) == ["uris": "spotify:track:a"])
        try await harness.client.saveToLibrary([])
        #expect(harness.apiRequests.count == 2)
    }
}

struct WebClientCommandTests {
    @Test func playBuildsContextAndTrackBodies() async throws {
        let harness = try await Harness()
        harness.router.on("PUT /me/player/play", status: 204)

        try await harness.client.play(.context("spotify:playlist:pl-own", offset: .index(3)), deviceID: "dev-mac")
        var request = try #require(harness.lastRequest("PUT /me/player/play"))
        #expect(HTTP.query(request) == ["device_id": "dev-mac"])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        var body = HTTP.jsonBody(request)
        #expect(body["context_uri"] as? String == "spotify:playlist:pl-own")
        #expect((body["offset"] as? [String: Any])?["position"] as? Int == 3)
        #expect(body["uris"] == nil)

        try await harness.client.play(.tracks(["spotify:track:a", "spotify:track:b"], offset: .track("spotify:track:b")), deviceID: nil)
        request = try #require(harness.lastRequest("PUT /me/player/play"))
        #expect(request.url?.query == nil)
        body = HTTP.jsonBody(request)
        #expect(body["uris"] as? [String] == ["spotify:track:a", "spotify:track:b"])
        #expect((body["offset"] as? [String: Any])?["uri"] as? String == "spotify:track:b")
        #expect(body["context_uri"] == nil)
    }

    @Test func transportCommandsHitTheDocumentedEndpoints() async throws {
        let harness = try await Harness()
        for route in ["PUT /me/player", "PUT /me/player/play", "PUT /me/player/pause", "POST /me/player/next",
                      "POST /me/player/previous", "PUT /me/player/seek", "PUT /me/player/volume",
                      "PUT /me/player/shuffle", "PUT /me/player/repeat", "POST /me/player/queue"] {
            harness.router.on(route, status: 204)
        }
        let client = harness.client
        try await client.transferPlayback(to: "dev-tv", play: true)
        try await client.resume(deviceID: nil)
        try await client.pause(deviceID: "d")
        try await client.skipToNext(deviceID: nil)
        try await client.skipToPrevious(deviceID: nil)
        try await client.seek(to: 61.2345, deviceID: nil)
        try await client.setVolume(140, deviceID: "d")
        try await client.setShuffle(true, deviceID: nil)
        try await client.setRepeat(.track, deviceID: nil)
        try await client.addToQueue("spotify:track:a", deviceID: nil)

        let transfer = try #require(harness.lastRequest("PUT /me/player"))
        #expect(HTTP.jsonBody(transfer)["device_ids"] as? [String] == ["dev-tv"])
        #expect(HTTP.jsonBody(transfer)["play"] as? Bool == true)
        #expect(try #require(harness.lastRequest("PUT /me/player/play")).httpBody == Data())
        #expect(HTTP.query(try #require(harness.lastRequest("PUT /me/player/pause"))) == ["device_id": "d"])
        #expect(HTTP.query(try #require(harness.lastRequest("PUT /me/player/seek"))) == ["position_ms": "61235"])
        #expect(HTTP.query(try #require(harness.lastRequest("PUT /me/player/volume"))) == ["volume_percent": "100", "device_id": "d"])
        #expect(HTTP.query(try #require(harness.lastRequest("PUT /me/player/shuffle"))) == ["state": "true"])
        #expect(HTTP.query(try #require(harness.lastRequest("PUT /me/player/repeat"))) == ["state": "track"])
        #expect(HTTP.query(try #require(harness.lastRequest("POST /me/player/queue"))) == ["uri": "spotify:track:a"])
    }

    @Test func pausingWhilePausedIsNotAnError() async throws {
        let harness = try await Harness()
        harness.router.on("PUT /me/player/pause", status: 403, json: Fixtures.error(status: 403, message: "Player command failed: Already paused", reason: "ALREADY_PAUSED"))
        try await harness.client.pause(deviceID: nil)
    }

    @Test func likedSongsPlaysAsTheUserCollectionContext() async throws {
        let harness = try await Harness()
        harness.router.on("PUT /me/player/play", status: 204)
        try await harness.client.play(.context(.likedSongs(userID: "tony")), deviceID: nil)
        let body = HTTP.jsonBody(try #require(harness.lastRequest("PUT /me/player/play")))
        #expect(body["context_uri"] as? String == "spotify:user:tony:collection")
    }

    @Test func likedSongsFallsBackToSavedTracksWhenTheContextIsRejected() async throws {
        let harness = try await Harness()
        harness.router.on("PUT /me/player/play", status: 400, json: Fixtures.error(status: 400, message: "Non supported context uri"))
        harness.router.on("PUT /me/player/play", status: 204)
        harness.router.on("GET /me/tracks", json: Fixtures.savedTracks)

        try await harness.client.play(.context(.likedSongs(userID: "tony"), offset: .track("spotify:track:trk1")), deviceID: nil)
        var body = HTTP.jsonBody(try #require(harness.lastRequest("PUT /me/player/play")))
        // The unplayable saved track is left out.
        #expect(body["uris"] as? [String] == ["spotify:track:trk1"])
        #expect((body["offset"] as? [String: Any])?["uri"] as? String == "spotify:track:trk1")

        try await harness.client.play(.context(.likedSongs(userID: "tony")), deviceID: nil)
        body = HTTP.jsonBody(try #require(harness.lastRequest("PUT /me/player/play")))
        #expect(body["uris"] as? [String] == ["spotify:track:trk1"])
        // The rejection is remembered: the second play skips the context attempt.
        #expect(harness.apiRequests.filter { $0.url?.path == "/v1/me/player/play" }.count == 3)
    }
}

struct WebClientErrorTests {
    private func failure(status: Int, json: String = "", headers: [String: String] = [:], route: String = "GET /me/player/devices") async throws -> OrbitError? {
        let harness = try await Harness()
        harness.router.on(route, status: status, json: json, headers: headers)
        do {
            switch route {
            case "GET /me/player/devices": _ = try await harness.client.devices()
            case "GET /playlists/p/items": _ = try await harness.client.playlistItems(playlistID: "p", page: PageRequest())
            case "GET /me/tracks": _ = try await harness.client.savedTracks(PageRequest())
            default: Issue.record("Unhandled route")
            }
            return nil
        } catch {
            return error
        }
    }

    @Test func unauthorizedRefreshesAndRetriesOnce() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/devices", status: 401, json: Fixtures.error(status: 401, message: "The access token expired"))
        harness.router.on("GET /me/player/devices", json: Fixtures.devices)
        let devices = try await harness.client.devices()
        #expect(devices.count == 3)
        let attempts = harness.apiRequests.filter { $0.url?.path == "/v1/me/player/devices" }
        #expect(attempts.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer access-1", "Bearer access-2"])
        #expect(harness.transport.tokenRequests.count == 1)
    }

    @Test func secondUnauthorizedIsAuthExpired() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/devices", status: 401)
        await #expect(throws: OrbitError.authExpired) { try await harness.client.devices() }
        #expect(harness.apiRequests.count == 2)
    }

    @Test func forbiddenIsDistinguishedByPayloadAndEndpoint() async throws {
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Check settings on developer.spotify.com/dashboard, the user may not be registered."), route: "GET /me/tracks") == .notAllowlisted)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Forbidden"), route: "GET /me/tracks") == .notAllowlisted)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Player command failed: Premium required", reason: "PREMIUM_REQUIRED")) == .premiumRequired)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Player command failed", reason: "DEVICE_NOT_CONTROLLABLE")) == .deviceRestricted)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Player command failed", reason: "CONTEXT_DISALLOW")) == .contentRestricted)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Player command failed: Restriction violated", reason: "UNKNOWN")) == .deviceRestricted)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Forbidden"), route: "GET /playlists/p/items") == .playlistItemsUnavailable)
        #expect(try await failure(status: 403, json: Fixtures.error(status: 403, message: "Insufficient client scope"), route: "GET /me/tracks") == .authExpired)
        #expect(try await failure(status: 403, json: "not json") == .deviceRestricted)
    }

    @Test func notFoundIsNoActiveDeviceOnlyForPlayerEndpoints() async throws {
        #expect(try await failure(status: 404, json: Fixtures.error(status: 404, message: "Player command failed: No active device found", reason: "NO_ACTIVE_DEVICE")) == .noActiveDevice)
        #expect(try await failure(status: 404, json: Fixtures.error(status: 404, message: "Resource not found"), route: "GET /playlists/p/items") == .notFound)
    }

    @Test func rateLimitHonorsRetryAfterAndFailsFastWhileWaiting() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/devices", status: 429, headers: ["Retry-After": "12"])
        harness.router.on("GET /me/player/devices", json: Fixtures.devices)

        await #expect(throws: OrbitError.rateLimited(retryAfter: 12)) { try await harness.client.devices() }
        harness.clock.advance(by: 5)
        await #expect(throws: OrbitError.rateLimited(retryAfter: 7)) { try await harness.client.devices() }
        await #expect(throws: OrbitError.rateLimited(retryAfter: 7)) { try await harness.client.currentUser() }
        #expect(harness.apiRequests.count == 1)

        harness.clock.advance(by: 7.5)
        #expect(try await harness.client.devices().count == 3)
    }

    @Test func quotaExhaustionIsDistinguishedAndBacksOffWithoutRetryAfter() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/devices", status: 429, json: #"{"error": {"status": 429, "message": "Too many requests", "reason": "QUOTA_EXCEEDED"}}"#)
        await #expect(throws: OrbitError.quotaExceeded(retryAfter: 120)) { try await harness.client.devices() }
        harness.clock.advance(by: 20)
        await #expect(throws: OrbitError.quotaExceeded(retryAfter: 100)) { try await harness.client.devices() }
        #expect(harness.apiRequests.count == 1)
    }

    @Test func plainRateLimitWithoutRetryAfterWaitsOneWindow() async throws {
        #expect(try await failure(status: 429, json: Fixtures.error(status: 429, message: "API rate limit exceeded")) == .rateLimited(retryAfter: 30))
    }

    @Test func networkAndServerFailures() async throws {
        let harness = try await Harness()
        let offline = StubTransport { _ throws(OrbitError) in throw .network(detail: "URLError -1009") }
        let client = SpotifyWebClient(authorizer: harness.authorizer, transport: offline, now: { harness.clock.now })
        await #expect(throws: OrbitError.network(detail: "URLError -1009")) { try await client.devices() }
        #expect(try await failure(status: 503) == .network(detail: "Spotify returned HTTP 503."))
        #expect(try await failure(status: 500, json: Fixtures.error(status: 500, message: "Server error")) == .unexpected(detail: "HTTP 500: Server error"))
    }

    @Test func malformedBodiesFailTyped() async throws {
        let harness = try await Harness()
        harness.router.on("GET /me/player/devices", json: "<html>")
        await #expect(throws: OrbitError.self) { try await harness.client.devices() }
    }

    @Test func signedOutClientSendsNothing() async throws {
        let harness = try await Harness()
        await harness.authorizer.signOut()
        await #expect(throws: OrbitError.notSignedIn) { try await harness.client.devices() }
        #expect(harness.apiRequests.isEmpty)
    }
}
