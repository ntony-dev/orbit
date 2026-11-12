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
