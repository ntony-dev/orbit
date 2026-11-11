import Foundation
import OrbitCore

// Debug-only launch arguments that put the UI into a known state for screenshots without simulated input, and
// without writing to the user's Preferences:
//   --ui-screen player|picker|library|liked|queue|search|devices|playlist:<id>
//   --ui-hover                     show the pill's hover controls
//   --ui-scenario <name>           with --demo only: signed-out, automation-denied, spotify-closed, idle,
//                                  rate-limited, empty-library, switch-fails
//   --ui-glass clear|balanced|tinted, --ui-opacity 0...1, --ui-accent neutral|mint|ice|amber|lavender,
//   --ui-pill compact|regular, --ui-no-artwork
//   --ui-reduce-transparency, --ui-increase-contrast, --ui-reduce-motion
struct UIDebugOptions {
    var screen: String?
    var forcesPillHover = false
    var scenario: String?
    var glassPreset: GlassPreset?
    var backgroundOpacity: Double?
    var accent: AccentChoice?
    var pillSize: PillSize?
    var hidesArtwork = false
    var reducesTransparency = false
    var increasesContrast = false
    var reducesMotion = false

    #if DEBUG
    static let current = UIDebugOptions(arguments: ProcessInfo.processInfo.arguments)
    #else
    static let current = UIDebugOptions()
    #endif

    init() {}

    init(arguments: [String]) {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        screen = value("--ui-screen")
        forcesPillHover = arguments.contains("--ui-hover")
        if arguments.contains("--demo") { scenario = value("--ui-scenario") }
        glassPreset = value("--ui-glass").flatMap(GlassPreset.init(rawValue:))
        backgroundOpacity = value("--ui-opacity").flatMap(Double.init)
        accent = value("--ui-accent").flatMap { name in
            AccentChoice.presets.first { "\($0)" == name }
        }
        pillSize = value("--ui-pill").flatMap(PillSize.init(rawValue:))
        hidesArtwork = arguments.contains("--ui-no-artwork")
        reducesTransparency = arguments.contains("--ui-reduce-transparency")
        increasesContrast = arguments.contains("--ui-increase-contrast")
        reducesMotion = arguments.contains("--ui-reduce-motion")
    }
}
