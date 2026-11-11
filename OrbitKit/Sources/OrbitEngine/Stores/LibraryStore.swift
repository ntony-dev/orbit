import Foundation
import Observation
import OrbitCore

// Pinned and recent playlists live here, not in Preferences. This first pass keeps them in memory only.
@MainActor
@Observable
public final class LibraryStore {
    public static let recentLimit = 8

    public private(set) var playlists: LoadState<[Playlist]> = .idle
    public private(set) var pinnedPlaylists: [Playlist] = []
    public private(set) var recentPlaylists: [Playlist] = []
    // A playlist the user cannot read resolves to `.failed(.playlistItemsUnavailable)`; it can still be played.
    public private(set) var playlistItems: [Playlist.ID: LoadState<[Track]>] = [:]
    public private(set) var savedTracks: LoadState<[Track]> = .idle
    public private(set) var searchQuery = ""
    public private(set) var searchResults: LoadState<SearchResults> = .idle
    public private(set) var queue: LoadState<PlaybackQueue> = .idle
    public private(set) var devices: LoadState<[PlaybackDevice]> = .idle

    @ObservationIgnored private let api: any SpotifyAPI

    public init(api: any SpotifyAPI) {
        self.api = api
    }

    public func loadPlaylists() async {
        playlists = .loading
        playlists = await loadAll { [api] (page) async throws(OrbitError) in try await api.playlists(page) }
    }

    public func items(for playlist: Playlist) -> LoadState<[Track]> {
        playlistItems[playlist.id] ?? .idle
    }

    public func loadItems(for playlist: Playlist) async {
        guard playlist.canReadItems else {
            playlistItems[playlist.id] = .failed(.playlistItemsUnavailable)
            return
        }
        playlistItems[playlist.id] = .loading
        playlistItems[playlist.id] = await loadAll { [api] (page) async throws(OrbitError) in
            try await api.playlistItems(playlistID: playlist.id, page: page)
        }
    }

    public func loadSavedTracks() async {
        savedTracks = .loading
        savedTracks = await loadAll { [api] (page) async throws(OrbitError) in try await api.savedTracks(page) }
    }

    public func search(_ query: String) async {
        searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = .idle
            return
        }
        searchResults = .loading
        let result: LoadState<SearchResults>
        do {
            result = .loaded(try await api.search(trimmed, categories: Set(SearchCategory.allCases), page: PageRequest(limit: 10)))
        } catch {
            result = .failed(error)
        }
        // A slower, older query must not overwrite the results of the one the user is looking at.
        if searchQuery == query { searchResults = result }
    }

    public func loadQueue() async {
        queue = .loading
        do {
            queue = .loaded(try await api.queue())
        } catch {
            queue = .failed(error)
        }
    }

    public func addToQueue(_ track: Track) async {
        do {
            try await api.addToQueue(track.uri, deviceID: nil)
            await loadQueue()
        } catch {
            queue = .failed(error)
        }
    }

    public func loadDevices() async {
        devices = .loading
        do {
            devices = .loaded(try await api.devices())
        } catch {
            devices = .failed(error)
        }
    }

    public func isPinned(_ playlist: Playlist) -> Bool {
        pinnedPlaylists.contains { $0.id == playlist.id }
    }

    public func pin(_ playlist: Playlist) {
        guard !isPinned(playlist) else { return }
        pinnedPlaylists.append(playlist)
    }

    public func unpin(_ playlist: Playlist) {
        pinnedPlaylists.removeAll { $0.id == playlist.id }
    }

    public func movePinned(fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's onMove, without making the engine depend on SwiftUI.
        let moving = source.map { pinnedPlaylists[$0] }
        let insertion = destination - source.count(in: 0..<destination)
        pinnedPlaylists = pinnedPlaylists.indices.filter { !source.contains($0) }.map { pinnedPlaylists[$0] }
        pinnedPlaylists.insert(contentsOf: moving, at: insertion)
    }

    public func recordRecent(_ playlist: Playlist) {
        recentPlaylists.removeAll { $0.id == playlist.id }
        recentPlaylists.insert(playlist, at: 0)
        if recentPlaylists.count > Self.recentLimit {
            recentPlaylists.removeLast(recentPlaylists.count - Self.recentLimit)
        }
    }

    public func removeRecent(_ playlist: Playlist) {
        recentPlaylists.removeAll { $0.id == playlist.id }
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
