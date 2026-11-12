import Foundation
import Observation
import OrbitCore

// A track list shows from its first page; this is what is still to come below the rows already shown.
public enum RemainingPages: Equatable, Sendable {
    case loading
    // The rows already shown stay; loading again continues from the first page that failed.
    case failed(OrbitError)
}

public enum PreferredDeviceStatus: Hashable, Sendable {
    case notSet
    // The device list has not been loaded yet, so the saved device is neither confirmed nor ruled out.
    case unverified(DeviceReference)
    case available(PlaybackDevice)
    // Saved in settings but absent from Spotify's device list: asleep, signed out or gone for good.
    case missing(DeviceReference)
}

// Library data from the Web API, cached briefly so reopening the library is instant and several views asking for
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
        // How many opened playlists keep their tracks and how many searches keep their results. Revisiting one
        // of the most recent is instant; older ones load again as on a first visit.
        public var playlistsKept = 12
        public var searchesKept = 24

        public init() {}
    }

    public private(set) var playlists: LoadState<[Playlist]> = .idle
    public private(set) var pinnedPlaylists: [Playlist] = []
    public private(set) var recentPlaylists: [Playlist] = []
    // A playlist the user cannot read resolves to `.failed(.playlistItemsUnavailable)`; it can still be played.
    public private(set) var playlistItems: [Playlist.ID: LoadState<[Track]>] = [:]
    // Present while a list shows only its first pages; absent once the list is complete.
    public private(set) var remainingItems: [Playlist.ID: RemainingPages] = [:]
    // Loaded only when Liked Songs is opened; the Library's row shows `likedSongsCount` without it.
    public private(set) var savedTracks: LoadState<[Track]> = .idle
    public private(set) var remainingSavedTracks: RemainingPages?
    // Spotify's own count of saved tracks, from a one-item page.
    public private(set) var likedSongsTotal: Int?
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
    // Playlists whose tracks are kept, least recently shown first.
    @ObservationIgnored private var itemsRecency: [Playlist.ID] = []
    // Where a partly shown list continues.
    @ObservationIgnored private var nextPage: [CacheKey: PageRequest] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var shelfRestore: Task<Void, Never>?
    @ObservationIgnored private var shelfRevision = 0
    @ObservationIgnored private var generation = 0

    private enum CacheKey: Hashable {
        case playlists, savedTracks, likedSongsTotal, queue, devices
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
        guard let items = playlistItems[playlist.id] else { return .idle }
        touchItems(playlist.id)
        return items
    }

    public func remainingPages(for playlist: Playlist) -> RemainingPages? {
        playlist.id == LikedSongs.playlistID ? remainingSavedTracks : remainingItems[playlist.id]
    }

    // Rows show as soon as the first page arrives and later pages append below them. A list already complete on
    // screen is refreshed whole instead, so it never shrinks to one page and grows back.
    public func loadItems(for playlist: Playlist, force: Bool = false) async {
        if playlist.id == LikedSongs.playlistID {
            await loadSavedTracks(force: force)
            return
        }
        guard playlist.canReadItems else {
            playlistItems[playlist.id] = .failed(.playlistItemsUnavailable)
            return
        }
        let id = playlist.id
        await load(.items(id), lifetime: timing.itemsLifetime, force: force) { [self] isCurrent in
            let failure = await loadPages(
                .items(id),
                shown: { playlistItems[id] ?? .idle },
                remaining: { remainingItems[id] },
                show: { list, remaining in
                    playlistItems[id] = list
                    remainingItems[id] = remaining
                },
                isCurrent: isCurrent
            ) { [api] (page) async throws(OrbitError) in
                try await api.playlistItems(playlistID: id, page: page)
            }
            guard isCurrent() else { return false }
            touchItems(id)
            evictItems()
            if failure == .notFound { markMissing(playlist.uri) }
            return failure == nil
        }
    }

    public func loadSavedTracks(force: Bool = false) async {
        await load(.savedTracks, lifetime: timing.itemsLifetime, force: force) { [self] isCurrent in
            let failure = await loadPages(
                .savedTracks,
                shown: { savedTracks },
                remaining: { remainingSavedTracks },
                show: { list, remaining in
                    savedTracks = list
                    remainingSavedTracks = remaining
                    likedSongs?.itemCount = likedSongsCount
                },
                isCurrent: isCurrent
            ) { [api, weak self] (page) async throws(OrbitError) in
                let loaded = try await api.savedTracks(page)
                if let total = loaded.total { self?.likedSongsTotal = total }
                return loaded
            }
            return failure == nil
        }
    }

    // The loaded list once Liked Songs has been opened, so the row and the list agree; until then Spotify's total,
    // which also counts the rare saved entry Spotify returns without a track.
    public var likedSongsCount: Int? {
        if remainingSavedTracks == nil, let loaded = savedTracks.value { return loaded.count }
        return likedSongsTotal
    }

    // One request whatever the size of the collection: a one-item page carries the total.
    public func loadLikedSongsCount(force: Bool = false) async {
        if !force, savedTracks.value != nil, remainingSavedTracks == nil { return }
        await load(.likedSongsTotal, lifetime: timing.itemsLifetime, force: force) { [self] isCurrent in
            do throws(OrbitError) {
                let page = try await api.savedTracks(PageRequest(offset: 0, limit: 1))
                guard isCurrent(), let total = page.total else { return false }
                likedSongsTotal = total
                likedSongs?.itemCount = likedSongsCount
                return true
            } catch {
                return false
            }
        }
    }

    // Track URIs of a context whose items are all loaded, so the coordinator can recognise a confirmed switch; a
    // list still paging in would reject the tracks on its later pages.
    func knownTrackURIs(for uri: SpotifyURI) -> Set<SpotifyURI>? {
        if LikedSongs.isLikedSongs(uri) {
            guard remainingSavedTracks == nil else { return nil }
            return savedTracks.value.map { Set($0.map(\.uri)) }
        }
        guard let playlist = playlist(for: uri), remainingItems[playlist.id] == nil else { return nil }
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
            cacheSearch(found, for: key)
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
        likedSongs = LikedSongs.playlist(userID: profile.id, ownerName: profile.displayName, itemCount: likedSongsCount)
    }

    // Drops everything that came from the signed-in account; pins and recents are local and stay.
    func reset() {
        generation += 1
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        loadedAt.removeAll()
        searchCache.removeAll()
        itemsRecency.removeAll()
        searchTask?.cancel()
        playlists = .idle
        playlistItems = [:]
        remainingItems = [:]
        nextPage.removeAll()
        savedTracks = .idle
        remainingSavedTracks = nil
        likedSongsTotal = nil
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

    private func touchItems(_ id: Playlist.ID) {
        if itemsRecency.last == id { return }
        itemsRecency.removeAll { $0 == id }
        itemsRecency.append(id)
    }

    // Drops the tracks of the least recently shown playlists beyond the limit, never one still loading.
    private func evictItems() {
        var excess = itemsRecency.count - timing.playlistsKept
        var index = 0
        while excess > 0, index < itemsRecency.count {
            let id = itemsRecency[index]
            guard inFlight[.items(id)] == nil else {
                index += 1
                continue
            }
            itemsRecency.remove(at: index)
            playlistItems[id] = nil
            remainingItems[id] = nil
            nextPage[.items(id)] = nil
            loadedAt[.items(id)] = nil
            excess -= 1
        }
    }

    // Expired results are never shown again, so they go first; then the oldest beyond the limit.
    private func cacheSearch(_ results: SearchResults, for key: String) {
        let now = clock.now()
        searchCache = searchCache.filter { now.timeIntervalSince($0.value.at) < timing.searchLifetime }
        searchCache[key] = (results, now)
        let excess = searchCache.count - timing.searchesKept
        guard excess > 0 else { return }
        for old in searchCache.sorted(by: { $0.value.at < $1.value.at }).prefix(excess).map(\.key) {
            searchCache[old] = nil
        }
    }

    // Returns the failure, if any. A first load shows each page as it lands and a failed later page keeps the rows
    // already shown; a partly shown list continues where it stopped; a complete list stays on screen until its
    // refreshed replacement has loaded whole, or until Spotify says its items are unavailable.
    private func loadPages<Item: Sendable>(
        _ key: CacheKey,
        shown: () -> LoadState<[Item]>,
        remaining: () -> RemainingPages?,
        show: (LoadState<[Item]>, RemainingPages?) -> Void,
        isCurrent: () -> Bool,
        fetch: (PageRequest) async throws(OrbitError) -> Page<Item>
    ) async -> OrbitError? {
        let onScreen = shown().value
        let isRefresh = onScreen != nil && remaining() == nil
        var items: [Item] = []
        var request: PageRequest? = PageRequest()
        if !isRefresh, let onScreen, let resume = nextPage[key] {
            items = onScreen
            request = resume
            show(.loaded(onScreen), .loading)
        } else if onScreen == nil {
            show(.loading, nil)
        }
        do {
            while let current = request {
                let page = try await fetch(current)
                guard isCurrent() else { return nil }
                items += page.items
                request = page.nextRequest(limit: current.limit)
                guard !isRefresh else { continue }
                nextPage[key] = request
                show(.loaded(items), request == nil ? nil : .loading)
            }
            if isRefresh { show(.loaded(items), nil) }
            return nil
        } catch {
            guard isCurrent() else { return error }
            if !isRefresh, !items.isEmpty, error != .playlistItemsUnavailable {
                show(.loaded(items), .failed(error))
            } else if onScreen == nil || error == .playlistItemsUnavailable {
                nextPage[key] = nil
                show(.failed(error), nil)
            }
            return error
        }
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
