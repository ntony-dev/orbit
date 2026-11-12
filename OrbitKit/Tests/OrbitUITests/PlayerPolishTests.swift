import OrbitCore
@testable import OrbitUI
import SwiftUI
import Testing

struct PlaybackStatusTests {
    private func status(
        hasTrack: Bool = false,
        isPlaying: Bool = false,
        installed: Bool = true,
        running: Bool = true,
        automation: AutomationPermission = .granted,
        signedIn: Bool = true
    ) -> PlaybackStatus {
        PlaybackStatus(
            hasTrack: hasTrack, isPlaying: isPlaying, isSpotifyInstalled: installed,
            isSpotifyRunning: running, automation: automation, isSignedIn: signedIn
        )
    }

    @Test func undeterminedPermissionAsksInsteadOfClaimingNothingIsPlaying() {
        #expect(status(automation: .notDetermined) == .automationNeeded)
        #expect(status(automation: .notDetermined, signedIn: false) == .automationNeeded)
        #expect(status(automation: .denied) == .automationDenied)
        #expect(status(automation: .granted) == .idle(canBrowse: true))
    }

    @Test func aKnownTrackWinsOverPermissionState() {
        #expect(status(hasTrack: true, isPlaying: true, automation: .notDetermined) == .playing)
        #expect(status(hasTrack: true, automation: .denied) == .paused)
    }

    @Test func spotifyAvailabilityComesBeforePermission() {
        #expect(status(installed: false, automation: .notDetermined) == .spotifyNotInstalled)
        #expect(status(running: false, automation: .requiresSpotifyRunning) == .spotifyClosed)
    }
}

struct PlayerKeyCommandTests {
    @Test func mirrorsSpotifyDesktopShortcuts() {
        #expect(PlayerKeyCommand.command(for: .space, modifiers: []) == .togglePlayback)
        #expect(PlayerKeyCommand.command(for: .leftArrow, modifiers: []) == .seek(by: -PlayerKeyCommand.seekStep))
        #expect(PlayerKeyCommand.command(for: .rightArrow, modifiers: [.numericPad]) == .seek(by: PlayerKeyCommand.seekStep))
        #expect(PlayerKeyCommand.command(for: .leftArrow, modifiers: .command) == .previousTrack)
        #expect(PlayerKeyCommand.command(for: .rightArrow, modifiers: .command) == .nextTrack)
        #expect(PlayerKeyCommand.command(for: .upArrow, modifiers: .command) == .changeVolume(by: PlayerKeyCommand.volumeStep))
        #expect(PlayerKeyCommand.command(for: .downArrow, modifiers: .command) == .changeVolume(by: -PlayerKeyCommand.volumeStep))
    }

    @Test func leavesOtherKeysAndModifiersAlone() {
        #expect(PlayerKeyCommand.command(for: .upArrow, modifiers: []) == nil)
        #expect(PlayerKeyCommand.command(for: .space, modifiers: .command) == nil)
        #expect(PlayerKeyCommand.command(for: .space, modifiers: .shift) == nil)
        #expect(PlayerKeyCommand.command(for: .leftArrow, modifiers: .option) == nil)
        #expect(PlayerKeyCommand.command(for: "k", modifiers: []) == nil)
    }
}

struct LegibilityTests {
    @Test func clearGlassKeepsADimmingFloorAtZeroBacking() {
        var theme = OrbitTheme.standard
        theme.glassPreset = .clear
        theme.backgroundOpacity = 0
        for scheme in [ColorScheme.light, .dark] {
            #expect(theme.surfaceFill(for: scheme) == theme.legibilityFloor(for: scheme))
            #expect(theme.surfaceFill(for: scheme) >= 0.4)
        }
    }

    // The setting has to visibly change every preset, Clear included, rather than only what a floor leaves over.
    @Test func backgroundOpacitySpansAWideRangeInEveryPreset() {
        for preset in GlassPreset.allCases {
            var theme = OrbitTheme.standard
            theme.glassPreset = preset
            for scheme in [ColorScheme.light, .dark] {
                theme.backgroundOpacity = 0
                let lowest = theme.surfaceFill(for: scheme)
                theme.backgroundOpacity = 1
                #expect(theme.surfaceFill(for: scheme) - lowest >= 0.3)
            }
        }
    }

    @Test func fillRisesWithTheSettingButNeverHidesTheGlass() {
        for preset in GlassPreset.allCases {
            var theme = OrbitTheme.standard
            theme.glassPreset = preset
            for scheme in [ColorScheme.light, .dark] {
                var previous = -1.0
                for step in 0...10 {
                    theme.backgroundOpacity = Double(step) / 10
                    let fill = theme.surfaceFill(for: scheme)
                    #expect(fill > previous)
                    #expect(fill < 0.9)
                    previous = fill
                }
            }
        }
    }

    @Test func reducedTransparencyIsNearlyOpaque() {
        var theme = OrbitTheme.standard
        theme.reducesTransparency = true
        #expect(theme.surfaceFill(for: .dark) > 0.9)
        #expect(theme.surfaceFill(for: .light) > 0.9)
    }

    @Test func disabledControlsStayStrongerOnLightGlass() {
        #expect(OrbitPalette.disabledOpacity(.light, contrast: .standard) > OrbitPalette.disabledOpacity(.dark, contrast: .standard))
        #expect(OrbitPalette.disabledOpacity(.light, contrast: .increased) > OrbitPalette.disabledOpacity(.light, contrast: .standard))
    }
}
