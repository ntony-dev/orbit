import OrbitCore
@testable import OrbitUI
import Testing

struct PillDestinationTests {
    @Test func opensThePlayerWheneverItHasSomethingToSayOrAsk() {
        #expect(PlaybackStatus.automationNeeded.pillDestination == .player)
        #expect(PlaybackStatus.automationDenied.pillDestination == .player)
        #expect(PlaybackStatus.spotifyClosed.pillDestination == .player)
        #expect(PlaybackStatus.idle(canBrowse: false).pillDestination == .player)
        #expect(PlaybackStatus.paused.pillDestination == .player)
    }

    @Test func opensTheLibraryOnlyWhenAPlaylistCanBeStartedFromIt() {
        #expect(PlaybackStatus.idle(canBrowse: true).pillDestination == .playlistPicker)
    }
}

struct DebugBackdropOptionTests {
    @Test func backdropDefaultsToTheGradientAndTakesAStyle() {
        #expect(UIDebugOptions(arguments: ["--demo"]).backdrop == nil)
        #expect(UIDebugOptions(arguments: ["--ui-backdrop", "--demo"]).backdrop == .gradient)
        #expect(UIDebugOptions(arguments: ["--ui-backdrop"]).backdrop == .gradient)
        #expect(UIDebugOptions(arguments: ["--ui-backdrop", "bright"]).backdrop == .bright)
        #expect(UIDebugOptions(arguments: ["--demo", "--ui-backdrop", "busy"]).backdrop == .busy)
    }
}

struct DebugPlaybackOptionTests {
    @Test func playbackStatesAreReadOnlyInTheDemo() {
        let arguments = ["--ui-shuffle", "--ui-repeat", "one", "--ui-device", "dev-kitchen", "--ui-track-duration", "3754"]
        let demo = UIDebugOptions(arguments: ["--demo"] + arguments)
        #expect(demo.turnsShuffleOn)
        #expect(demo.repeatMode == .track)
        #expect(demo.deviceID == "dev-kitchen")
        #expect(demo.trackDuration == 3754)
        let real = UIDebugOptions(arguments: arguments)
        #expect(!real.turnsShuffleOn && real.repeatMode == nil && real.deviceID == nil && real.trackDuration == nil)
    }

    @Test func repeatTakesAllOrOne() {
        #expect(UIDebugOptions(arguments: ["--demo", "--ui-repeat", "all"]).repeatMode == .context)
        #expect(UIDebugOptions(arguments: ["--demo", "--ui-repeat", "sometimes"]).repeatMode == nil)
        #expect(UIDebugOptions(arguments: ["--demo", "--ui-track-duration", "-5"]).trackDuration == nil)
    }
}
