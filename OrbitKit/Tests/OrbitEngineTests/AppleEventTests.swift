import Foundation
import OrbitCore
@testable import OrbitEngine
import Synchronization
import Testing

struct AppleEventTests {
    private let target = NSAppleEventDescriptor(processIdentifier: getpid())

    private func code(_ value: FourCharCode) -> String {
        String(bytes: (0..<4).map { UInt8((value >> (24 - $0 * 8)) & 0xFF) }, encoding: .macOSRoman) ?? "?"
    }

    @Test(arguments: [
        (SpotifyAppleEvent.play, "spfyPlay"),
        (.pause, "spfyPaus"),
        (.playPause, "spfyPlPs"),
        (.nextTrack, "spfyNext"),
        (.previousTrack, "spfyPrev"),
        (.playTrack("spotify:track:abc", context: nil), "spfyPCtx"),
        (.setPosition(12), "coresetd"),
        (.appProperties, "coregetd"),
    ])
    func commandsUseTheDictionaryCodes(event: SpotifyAppleEvent, expected: String) {
        let descriptor = event.descriptor(target: target)
        #expect(code(descriptor.eventClass) + code(descriptor.eventID) == expected)
    }

    @Test func playTrackCarriesTheURIAndContext() {
        let descriptor = SpotifyAppleEvent.playTrack("spotify:track:abc", context: "spotify:playlist:xyz").descriptor(target: target)
        #expect(descriptor.paramDescriptor(forKeyword: fourCharCode("----"))?.stringValue == "spotify:track:abc")
        #expect(descriptor.paramDescriptor(forKeyword: fourCharCode("cotx"))?.stringValue == "spotify:playlist:xyz")
        let bare = SpotifyAppleEvent.playTrack("spotify:playlist:xyz", context: nil).descriptor(target: target)
        #expect(bare.paramDescriptor(forKeyword: fourCharCode("cotx")) == nil)
    }

    @Test func settersTargetTheRightPropertyAndClampValues() {
        let volume = SpotifyAppleEvent.setVolume(140).descriptor(target: target)
        let specifier = volume.paramDescriptor(forKeyword: fourCharCode("----"))
        #expect(specifier?.descriptorType == fourCharCode("obj "))
        #expect(specifier?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pVol"))
        #expect(volume.paramDescriptor(forKeyword: fourCharCode("data"))?.int32Value == 100)

        let position = SpotifyAppleEvent.setPosition(-3).descriptor(target: target)
        #expect(position.paramDescriptor(forKeyword: fourCharCode("data"))?.doubleValue == 0)
        let shuffle = SpotifyAppleEvent.setShuffling(true).descriptor(target: target)
        #expect(shuffle.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pShu"))
        #expect(shuffle.paramDescriptor(forKeyword: fourCharCode("data"))?.booleanValue == true)
        let repeating = SpotifyAppleEvent.setRepeating(false).descriptor(target: target)
        #expect(repeating.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pRep"))
    }

    @Test func trackPropertiesAreNestedUnderCurrentTrack() {
        let descriptor = SpotifyAppleEvent.trackProperty(.duration).descriptor(target: target)
        let specifier = descriptor.paramDescriptor(forKeyword: fourCharCode("----"))
        #expect(specifier?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pDur"))
        #expect(specifier?.forKeyword(fourCharCode("from"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("pTrk"))
    }

    @Test func eventErrorsMapToTypedErrors() {
        #expect(AppleEventChannel.error(for: -1743) == .automationDenied)
        #expect(AppleEventChannel.error(for: -600) == .spotifyNotRunning)
    }

    @Test func notificationPayloadParsesMillisecondDurations() {
        let state = SpotifyNotificationPayload.state(from: [
            "Player State": "Playing",
            "Track ID": "spotify:track:13VTgLuvMaP7OSHRM3l2B4",
            "Name": "Song",
            "Artist": "Artist",
            "Album": "Album",
            "Duration": NSNumber(value: 327_009),
            "Playback Position": NSNumber(value: 68.5),
        ])
        #expect(state?.status == .playing)
        #expect(state?.track?.id == "13VTgLuvMaP7OSHRM3l2B4")
        #expect(state?.track?.duration == 327.009)
        #expect(state?.position == 68.5)
        #expect(SpotifyNotificationPayload.state(from: ["Player State": "Stopped"])?.track == nil)
        #expect(SpotifyNotificationPayload.state(from: [:]) == nil)
    }

    // Orbit's panel never activates the app, and AppKit holds back distributed notifications while inactive.
    @MainActor
    @Test func stateNotificationsArriveWhileDeliveryIsSuspended() async throws {
        let name = Notification.Name("app.orbit.tests.\(UUID().uuidString)")
        let (stream, continuation) = AsyncStream.makeStream(of: SpotifyEventMonitor.Signal.self)
        let monitor = SpotifyEventMonitor(bundleIdentifier: "app.orbit.tests", stateChangedName: name, continuation: continuation)
        monitor.activate()
        defer { monitor.invalidate() }
        let center = DistributedNotificationCenter.default()
        center.suspended = true
        defer { center.suspended = false }
        center.postNotificationName(name, object: nil, userInfo: ["Player State": "Paused"], deliverImmediately: false)
        let received = Task { () -> LocalPlayerState.Status? in
            for await signal in stream {
                if case .stateChanged(let state) = signal { return state.status }
            }
            return nil
        }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(3))
            received.cancel()
            continuation.finish()
        }
        let status = await received.value
        timeout.cancel()
        #expect(status == .paused)
    }

    // The account store and the coordinator both subscribe; a notification must be enriched (two Apple events
    // with the track cached) once, not once per subscriber.
    @Test func everySubscriberSharesOneEnrichedSource() async throws {
        let hub = LocalEventHub()
        let starts = Mutex(0)
        let enrichments = Mutex(0)
        let (signals, feed) = AsyncStream.makeStream(of: LocalPlayerState.self)
        let start: (@escaping @Sendable (LocalPlayerEvent) -> Void) -> Void = { send in
            starts.withLock { $0 += 1 }
            Task {
                for await state in signals {
                    enrichments.withLock { $0 += 1 }
                    send(.stateChanged(state))
                }
            }
        }
        let account = hub.events(startingSource: start)
        let coordinator = hub.events(startingSource: start)
        feed.yield(LocalPlayerState(status: .paused))
        var accountIterator = account.makeAsyncIterator()
        var coordinatorIterator = coordinator.makeAsyncIterator()
        #expect(await accountIterator.next() == .stateChanged(LocalPlayerState(status: .paused)))
        #expect(await coordinatorIterator.next() == .stateChanged(LocalPlayerState(status: .paused)))
        #expect(starts.withLock { $0 } == 1)
        #expect(enrichments.withLock { $0 } == 1)
    }

    // Read-only check against the real app, opt-in because it needs Spotify running and Automation consent.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORBIT_READ_REAL_SPOTIFY"] == "1"))
    func theRealAppsMillisecondDurationsAreReadAsSeconds() async throws {
        let player = SpotifyAppleScriptPlayer()
        guard await player.isRunning(), await player.automationPermission(prompting: false) == .granted else { return }
        let state = try await player.state()
        #expect(state.track?.duration ?? 0 < 3600)
    }
}
