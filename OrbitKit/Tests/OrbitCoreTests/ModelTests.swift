import Foundation
import OrbitCore
import Testing

struct SpotifyURITests {
    @Test func parsesKindAndID() {
        let uri: SpotifyURI = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"
        #expect(uri.kind == .playlist)
        #expect(uri.id == "37i9dQZF1DXcBWIGoYBM5M")
    }

    @Test func treatsLikedSongsAsCollection() {
        let uri: SpotifyURI = "spotify:user:someone:collection"
        #expect(uri.kind == .collection)
        #expect(uri.id == nil)
    }

    @Test func rejectsNonSpotifyStrings() {
        #expect(SpotifyURI(rawValue: "https://open.spotify.com/track/abc").kind == nil)
    }

    @Test func buildsFromKindAndID() {
        #expect(SpotifyURI(.track, id: "abc").rawValue == "spotify:track:abc")
    }

    @Test func encodesAsPlainString() throws {
        let data = try JSONEncoder().encode(SpotifyURI(.album, id: "x"))
        #expect(String(decoding: data, as: UTF8.self) == "\"spotify:album:x\"")
    }
}

struct PlaybackSnapshotTests {
    private let track = Track(id: "t", name: "Song", artists: ["A"], album: "B", duration: 200)
    private let sampled = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func interpolatesWhilePlaying() {
        let snapshot = PlaybackSnapshot(track: track, isPlaying: true, position: 50, sampledAt: sampled)
        #expect(snapshot.position(at: sampled.addingTimeInterval(12)) == 62)
    }

    @Test func holdsPositionWhilePaused() {
        let snapshot = PlaybackSnapshot(track: track, isPlaying: false, position: 50, sampledAt: sampled)
        #expect(snapshot.position(at: sampled.addingTimeInterval(12)) == 50)
    }

    @Test func clampsToTrackDuration() {
        let snapshot = PlaybackSnapshot(track: track, isPlaying: true, position: 195, sampledAt: sampled)
        #expect(snapshot.position(at: sampled.addingTimeInterval(60)) == 200)
    }

    @Test func repeatModeCycles() {
        #expect(RepeatMode.off.next == .context)
        #expect(RepeatMode.context.next == .track)
        #expect(RepeatMode.track.next == .off)
    }
}

struct PageTests {
    @Test func nextRequestContinuesAfterReturnedItems() {
        let page = Page(items: [1, 2, 3], offset: 10, total: 20, hasMore: true)
        #expect(page.nextRequest(limit: 3) == PageRequest(offset: 13, limit: 3))
    }

    @Test func lastPageHasNoNextRequest() {
        #expect(Page(items: [1], offset: 0, hasMore: false).nextRequest(limit: 50) == nil)
    }
}

struct OrbitErrorTests {
    @Test func everyCaseHasAMessage() {
        let errors: [OrbitError] = [
            .spotifyNotInstalled, .spotifyNotRunning, .automationDenied, .notSignedIn, .authExpired, .notAllowlisted,
            .premiumRequired, .rateLimited(retryAfter: 30), .quotaExceeded(retryAfter: nil), .noActiveDevice,
            .deviceRestricted, .contentRestricted, .playlistItemsUnavailable, .network(detail: "offline"),
            .callbackPortInUse(port: 8888), .missingClientID, .cancelled, .notImplemented(feature: "X"),
            .unexpected(detail: "?"),
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(error.errorDescription == error.message)
        }
    }

    @Test func exposesRetryAfter() {
        #expect(OrbitError.rateLimited(retryAfter: 12).retryAfter == 12)
        #expect(OrbitError.quotaExceeded(retryAfter: 90).recoveryHint?.contains("minute") == true)
        #expect(OrbitError.noActiveDevice.retryAfter == nil)
    }
}

struct BroadcasterTests {
    @Test func deliversInitialValueThenUpdatesToEverySubscriber() async {
        let broadcaster = Broadcaster<Int>()
        let first = broadcaster.stream(initial: 0)
        let second = broadcaster.stream()
        broadcaster.send(1)
        broadcaster.finish()
        #expect(await Array(first) == [0, 1])
        #expect(await Array(second) == [1])
    }
}

extension Array {
    init<S: AsyncSequence>(_ sequence: S) async where S.Element == Element, S.Failure == Never {
        var elements: [Element] = []
        for await element in sequence { elements.append(element) }
        self = elements
    }
}
