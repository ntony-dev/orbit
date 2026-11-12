import Foundation
import Observation
import OrbitCore

public enum PreferredDeviceStatus: Hashable, Sendable {
    case notSet
    // The device list has not been loaded yet, so the saved device is neither confirmed nor ruled out.
    case unverified(DeviceReference)
    case available(PlaybackDevice)
    // Saved in settings but absent from Spotify's device list: asleep, signed out or gone for good.
    case missing(DeviceReference)
}

// Library data from the Web API, cached briefly so reopening the picker is instant and several views asking for
// the same thing share one request. Values stay visible while they refresh, and every load ends loaded or failed.
@MainActor
@Observable
public final class LibraryStore {
    public static let recentLimit = 8

    public struct Timing: Sendable {
        public var playlistsLifetime: TimeInterval = 300
        public var itemsLifetime: TimeInterval = 300
        public var queueLifetime: TimeInterval = 10
        public var devicesLifetime: TimeInterval = 15
        public var searchLifetime: TimeInterval = 120
        public var searchDebounce: Duration = .milliseconds(300)

        public init() {}
    }

    public private(set) var playlists: LoadState<[Playlist]> = .idle
    public private(set) var pinnedPlaylists: [Playlist] = []
    public private(set) var recentPlaylists: [Playlist] = []
    // A playlist the user cannot read resolves to `.failed(.playlistItemsUnavailable)`; it can still be played.
    public private(set) var playlistItems: [Playlist.ID: LoadState<[Track]>] = [:]
    public private(set) var savedTracks: LoadState<[Track]> = .idle
    public private(set) var searchQuery = ""
    // Keeps showing the previous query's results while a newer one loads, so refining never flashes empty;
    // `isSearching` says a newer query is still on its way.
    public private(set) var searchResults: LoadState<SearchResults> = .idle
    public private(set) var isSearching = false
    public private(set) var queue: LoadState<PlaybackQueue> = .idle
    public private(set) var devices: LoadState<[PlaybackDevice]> = .idle
    // Liked Songs as a playable, pinnable playlist; nil until the signed-in user is known.
    public private(set) var likedSongs: Playlist?
    // Pinned or recent playlists that the last full load no longer contained, e.g. deleted or unfollowed.
    public private(set) var missingPlaylistIDs: Set<Playlist.ID> = []
    // Failure of an action such as adding to the queue, kept apart from the load states it does not invalidate.
    public private(set) var lastError: OrbitError?

    @ObservationIgnored var preferredDevice: () -> DeviceReference? = { nil }

    @ObservationIgnored private let api: any SpotifyAPI
    @ObservationIgnored private let shelfFile: LibraryShelfFile?
    @ObservationIgnored private let clock: EngineClock
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var loadedAt: [CacheKey: Date] = [:]
    @ObservationIgnored private var inFlight: [CacheKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var searchCache: [String: (results: SearchResults, at: Date)] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var shelfRestore: Task<Void, Never>?
    @ObservationIgnored private var shelfRevision = 0
    @ObservationIgnored private var generation = 0

    private enum CacheKey: Hashable {
        case playlists, savedTracks, queue, devices
        case items(Playlist.ID)
    }

    public init(api: any SpotifyAPI, shelfFile: LibraryShelfFile? = nil, clock: EngineClock = .system, timing: Timing = Timing()) {
        self.api = api
        self.shelfFile = shelfFile
        self.clock = clock
        self.timing = timing
    }

    // Loads pins and recents from disk once; anything pinned before it finishes is kept.
    public func restoreShelf() async {
        if shelfRestore == nil {
            shelfRestore = Task { [weak self, shelfFile] in
                guard let stored = await shelfFile?.load() else { return }
                self?.merge(stored)
            }
        }
        await shelfRestore?.value
    }

    public var preferredDeviceStatus: PreferredDeviceStatus {
        guard let reference = preferredDevice() else { return .notSet }
        guard let list = devices.value else { return .unverified(reference) }
        if let device = list.first(where: { $0.id == reference.id }) ?? list.first(where: { $0.name == reference.name }) {
            return .available(device)
        }
        return .missing(reference)
    }

    public func playlist(for uri: SpotifyURI) -> Playlist? {
        if let likedSongs, LikedSongs.isLikedSongs(uri) { return likedSongs }
        return (playlists.value ?? []).first { $0.uri == uri }
            ?? pinnedPlaylists.first { $0.uri == uri }
            ?? recentPlaylists.first { $0.uri == uri }
    }

    public func loadPlaylists(force: Bool = false) async {
        await load(.playlists, lifetime: timing.playlistsLifetime, force: force) { [self] isCurrent in
            if playlists.value == nil { playlists = .loading }
            let result = await loadAll { [api] (page) async throws(OrbitError) in try await api.playlists(page) }
            guard isCurrent() else { return false }
            switch result {
            case .loaded(let all):
                playlists = result
                reconcileShelf(with: all)
                return true
            case .failed where playlists.value != nil:
                return false
            default:
                playlists = result
                return false
            }
        }
    }

    public func items(for playlist: Playlist) -> LoadState<[Track]> {
        if playlist.id == LikedSongs.playlistID { return savedTracks }
        return playlistItems[playlist.id] ?? .idle
    }

    public func loadItems(for playlist: Playlist, force: Bool = false) async {
        if playlist.id == LikedSongs.playlistID {
            await loadSavedTracks(force: force)
            return
        }
        guard playlist.canReadItems else {
            playlistItems[playlist.id] = .failed(.playlistItemsUnavailable)
            return
        }
        await load(.items(playlist.id), lifetime: timing.itemsLifetime, force: force) { [self] isCurrent in
            if playlistItems[playlist.id]?.value == nil { playlistItems[playlist.id] = .loading }
            let result = await loadAll { [api] (page) async throws(OrbitError) in
                try await api.playlistItems(playlistID: playlist.id, page: page)
            }
            guard isCurrent() else { return false }
            if result.value != nil || playlistItems[playlist.id]?.value == nil || result.error == .playlistItemsUnavailable {
                playlistItems[playlist.id] = result
            }
            if result.error == .notFound { markMissing(playlist.uri) }
            return result.value != nil
        }
    }

    public func loadSavedTracks(force: Bool = false) async {
        await load(.savedTracks, lifetime: timing.itemsLifetime, force: force) { [self] isCurrent in
            if savedTracks.value == nil { savedTracks = .loading }
            let result = await loadAll { [api] (page) async throws(OrbitError) in try await api.savedTracks(page) }
            guard isCurrent() else { return false }
            if result.value != nil || savedTracks.value == nil { savedTracks = result }
            if let count = result.value?.count { likedSongs?.itemCount = count }
            return result.value != nil
        }
    }

    // Track URIs of a context whose items are loaded, so the coordinator can recognise a confirmed switch.
    func knownTrackURIs(for uri: SpotifyURI) -> Set<SpotifyURI>? {
        if LikedSongs.isLikedSongs(uri) { return savedTracks.value.map { Set($0.map(\.uri)) } }
        guard let playlist = playlist(for: uri) else { return nil }
        return playlistItems[playlist.id]?.value.map { Set($0.map(\.uri)) }
    }

    // Runs immediately; views bound to a text field should use `updateSearch(_:)` instead.
    public func search(_ query: String) async {
        guard let key = beginSearch(query) else { return }
        let started = generation
        let result: LoadState<SearchResults>
        do {
            let found = try await api.search(key, categories: Set(SearchCategory.allCases), page: PageRequest(limit: 10))
            guard started == generation else { return }
            searchCache[key] = (found, clock.now())
            result = .loaded(found)
        } catch {
            result = .failed(error)
        }
        // A slower, older query must not overwrite the results of the one the user is looking at.
        if searchQuery == query {
            searchResults = result
            isSearching = false
        }
    }

    // Debounced and cancellable: each keystroke replaces the pending search, and only the last one is sent.
    public func updateSearch(_ query: String) {
        searchTask?.cancel()
        guard beginSearch(query) != nil else { return }
        searchTask = Task { [weak self, clock, timing] in
            do { try await clock.sleep(timing.searchDebounce) } catch { return }
            await self?.search(query)
        }
    }

    public func loadQueue(force: Bool = false) async {
        await load(.queue, lifetime: timing.queueLifetime, force: force) { [self] isCurrent in
            if queue.value == nil { queue = .loading }
            do throws(OrbitError) {
                let loaded = try await api.queue()
                guard isCurrent() else { return false }
                queue = .loaded(loaded)
                return true
            } catch {
                if isCurrent(), queue.value == nil { queue = .failed(error) }
                return false
            }
        }
    }

    @discardableResult
    public func addToQueue(_ track: Track) async -> Bool {
        do {
            try await api.addToQueue(track.uri, deviceID: nil)
            lastError = nil
            await loadQueue(force: true)
            return true
        } catch {
            lastError = error
            if queue.value == nil { queue = .failed(error) }
            return false
        }
    }

    public func loadDevices(force: Bool = false) async {
        await load(.devices, lifetime: timing.devicesLifetime, force: force) { [self] isCurrent in
            if devices.value == nil { devices = .loading }
            do throws(OrbitError) {
                let loaded = try await api.devices()
                guard isCurrent() else { return false }
                devices = .loaded(loaded)
                return true
            } catch {
                if isCurrent(), devices.value == nil { devices = .failed(error) }
                return false
            }
        }
    }

    public func dismissError() {
        lastError = nil
    }

    public func isPinned(_ playlist: Playlist) -> Bool {
        pinnedPlaylists.contains { $0.id == playlist.id }
    }

    public func pin(_ playlist: Playlist) {
        guard !isPinned(playlist) else { return }
        pinnedPlaylists.append(playlist)
        saveShelf()
    }

    public func unpin(_ playlist: Playlist) {
        pinnedPlaylists.removeAll { $0.id == playlist.id }
        saveShelf()
    }

    public func movePinned(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's onMove, without making the engine depend on SwiftUI.
        let moving = source.map { pinnedPlaylists[$0] }
        let insertion = destination - source.count(in: 0..<destination)
        pinnedPlaylists = pinnedPlaylists.indices.filter { !source.contains($0) }.map { pinnedPlaylists[$0] }
        pinnedPlaylists.insert(contentsOf: moving, at: insertion)
        saveShelf()
    }

    public func recordRecent(_ playlist: Playlist) {
        recentPlaylists.removeAll { $0.id == playlist.id }
        recentPlaylists.insert(playlist, at: 0)
        if recentPlaylists.count > Self.recentLimit {
            recentPlaylists.removeLast(recentPlaylists.count - Self.recentLimit)
        }
        missingPlaylistIDs.remove(playlist.id)
        saveShelf()
    }

    public func removeRecent(_ playlist: Playlist) {
        recentPlaylists.removeAll { $0.id == playlist.id }
        saveShelf()
    }

    // Spotify reported the playlist gone; it stays pinned and in recents, flagged like one missing from a full load.
    func markMissing(_ uri: SpotifyURI) {
        guard !LikedSongs.isLikedSongs(uri), let playlist = playlist(for: uri) else { return }
        missingPlaylistIDs.insert(playlist.id)
    }

    func setUser(_ profile: UserProfile?) {
        guard let profile else {
            likedSongs = nil
            return
        }
        guard likedSongs?.uri != .likedSongs(userID: profile.id) else { return }
        likedSongs = LikedSongs.playlist(userID: profile.id, ownerName: profile.displayName, itemCount: savedTracks.value?.count)
    }

    // Drops everything that came from the signed-in account; pins and recents are local and stay.
    func reset() {
        generation += 1
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        loadedAt.removeAll()
        searchCache.removeAll()
        searchTask?.cancel()
        playlists = .idle
        playlistItems = [:]
        savedTracks = .idle
        searchQuery = ""
        searchResults = .idle
        isSearching = false
        queue = .idle
        devices = .idle
        likedSongs = nil
        missingPlaylistIDs = []
        lastError = nil
    }

    private func load(
        _ key: CacheKey,
        lifetime: TimeInterval,
        force: Bool,
        // `isCurrent` turns false once `reset()` runs, so a load that outlives the account it began for writes nothing.
        _ body: @escaping @MainActor (_ isCurrent: @escaping @MainActor () -> Bool) async -> Bool
    ) async {
        if let running = inFlight[key] {
            await running.value
            return
        }
        if !force, let loaded = loadedAt[key], clock.now().timeIntervalSince(loaded) < lifetime { return }
        let started = generation
        let task = Task { @MainActor [weak self] in
            let succeeded = await body { [weak self] in self?.generation == started }
            guard let self, started == self.generation else { return }
            if succeeded { self.loadedAt[key] = self.clock.now() }
        }
        inFlight[key] = task
        await task.value
        if started == generation { inFlight[key] = nil }
    }

    private func merge(_ stored: LibraryShelf) {
        let pinnedIDs = Set(pinnedPlaylists.map(\.id))
        pinnedPlaylists = stored.pinned.filter { !pinnedIDs.contains($0.id) } + pinnedPlaylists
        let recentIDs = Set(recentPlaylists.map(\.id))
        recentPlaylists = Array((recentPlaylists + stored.recents.filter { !recentIDs.contains($0.id) }).prefix(Self.recentLimit))
    }

    // Refreshes names and artwork of pinned and recent playlists, and flags the ones that no longer exist.
    private func reconcileShelf(with all: [Playlist]) {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func refreshed(_ playlist: Playlist) -> Playlist { byID[playlist.id] ?? playlist }
        let shelf = pinnedPlaylists + recentPlaylists
        missingPlaylistIDs = Set(shelf.map(\.id).filter { byID[$0] == nil && $0 != LikedSongs.playlistID })
        let updatedPinned = pinnedPlaylists.map(refreshed)
        let updatedRecents = recentPlaylists.map(refreshed)
        guard updatedPinned != pinnedPlaylists || updatedRecents != recentPlaylists else { return }
        pinnedPlaylists = updatedPinned
        recentPlaylists = updatedRecents
        saveShelf()
    }

    private func saveShelf() {
        guard let shelfFile else { return }
        shelfRevision += 1
        let revision = shelfRevision
        let shelf = LibraryShelf(pinned: pinnedPlaylists, recents: recentPlaylists)
        Task { await shelfFile.save(shelf, revision: revision) }
    }

    // Settles an empty or cached query at once; otherwise marks the search in flight and returns the query to send.
    private func beginSearch(_ query: String) -> String? {
        searchQuery = query
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            searchResults = .idle
            isSearching = false
            return nil
        }
        if let cached = searchCache[key], clock.now().timeIntervalSince(cached.at) < timing.searchLifetime {
            searchResults = .loaded(cached.results)
            isSearching = false
            return nil
        }
        if searchResults.value == nil { searchResults = .loading }
        isSearching = true
        return key
    }

    private func loadAll<Item: Sendable>(
        _ fetch: (PageRequest) async throws(OrbitError) -> Page<Item>
    ) async -> LoadState<[Item]> {
        var items: [Item] = []
        var request: PageRequest? = PageRequest()
        do {
            while let current = request {
                let page = try await fetch(current)
                items += page.items
                request = page.nextRequest(limit: current.limit)
            }
            return .loaded(items)
        } catch {
            return .failed(error)
        }
    }
}
