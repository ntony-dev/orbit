import Foundation
import OrbitCore
import Testing

@MainActor
struct PreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let name = "orbit.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsWithDocumentedDefaults() {
        let preferences = Preferences(defaults: makeDefaults())
        #expect(preferences.appearance == .system)
        #expect(preferences.glassPreset == .balanced)
        #expect(!preferences.collapsesOnOutsideClick)
        #expect(preferences.collapsesAfterAction)
        #expect(preferences.accent == .neutral)
        #expect(preferences.alwaysOnTop)
        #expect(preferences.clientIDOverride == nil)
        #expect(preferences.savedPositions.isEmpty)
        #expect(preferences.syncFrequency == .standard)
    }

    @Test func persistsEveryKindOfValue() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.appearance = .dark
        preferences.accent = .custom(RGBColor(red: 0.1, green: 0.2, blue: 0.3))
        preferences.backgroundOpacity = 0.25
        preferences.pillSize = .compact
        preferences.savedPositions = ["display-1": SavedPanelPosition(x: 0.9, y: 0.1)]
        preferences.preferredDevice = DeviceReference(id: "dev", name: "Speaker")
        preferences.clientIDOverride = "abc"
        preferences.syncFrequency = .whileOpen
        preferences.collapsesOnOutsideClick = true

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.accent == .custom(RGBColor(red: 0.1, green: 0.2, blue: 0.3)))
        #expect(reloaded.backgroundOpacity == 0.25)
        #expect(reloaded.pillSize == .compact)
        #expect(reloaded.savedPositions["display-1"] == SavedPanelPosition(x: 0.9, y: 0.1))
        #expect(reloaded.preferredDevice == DeviceReference(id: "dev", name: "Speaker"))
        #expect(reloaded.clientIDOverride == "abc")
        #expect(reloaded.syncFrequency == .whileOpen)
        #expect(reloaded.collapsesOnOutsideClick)
    }

    // Changing the default must not change the look of an install that already chose a preset.
    @Test func aStoredGlassPresetSurvivesTheNewDefault() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).glassPreset = .clear
        #expect(Preferences(defaults: defaults).glassPreset == .clear)
    }

    @Test func clearingAnOptionalPersistsNil() {
        let defaults = makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.clientIDOverride = "abc"
        preferences.clientIDOverride = nil
        #expect(Preferences(defaults: defaults).clientIDOverride == nil)
    }
}
