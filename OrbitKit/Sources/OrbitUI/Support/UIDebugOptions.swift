import Foundation
import OrbitCore
import SwiftUI

// Debug-only launch arguments that put the UI into a known state for screenshots without simulated input, and
// without writing to the user's Preferences:
//   --ui-screen player|picker|library|liked|queue|search|devices|playlist:<id>
//   --ui-hover                     show the pill's hover controls
//   --ui-scenario <name>           with --demo only, read by the shell, which builds the scenario's stores:
//                                  signed-out, automation-denied, spotify-closed, idle, rate-limited,
//                                  empty-library, switch-fails
//   --ui-glass clear|balanced|tinted, --ui-opacity 0...1, --ui-accent neutral|mint|ice|amber|lavender,
//   --ui-pill compact|regular, --ui-no-artwork
//   --ui-reduce-transparency, --ui-increase-contrast, --ui-reduce-motion
//   --ui-tour                      expand, visit picker, library and player, then collapse, on a timer
//   --ui-slow <factor>             play every animation at this speed (0.1 is ten times slower)
//   --ui-switch <playlist-id>      two seconds after launch, switch to that playlist without collapsing
//   --ui-backdrop                  draw a stand-in wallpaper inside the canvas, because a capture of Orbit's
//                                  window alone cannot include what the glass refracts from behind it
struct UIDebugOptions {
    var screen: String?
    var forcesPillHover = false
    var glassPreset: GlassPreset?
    var backgroundOpacity: Double?
    var accent: AccentChoice?
    var pillSize: PillSize?
    var hidesArtwork = false
    var reducesTransparency = false
    var increasesContrast = false
    var reducesMotion = false
    var showsBackdrop = false
    var runsTour = false
    var switchPlaylistID: String?
    var animationSpeed: Double = 1

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
        showsBackdrop = arguments.contains("--ui-backdrop")
        runsTour = arguments.contains("--ui-tour")
        switchPlaylistID = value("--ui-switch")
        animationSpeed = value("--ui-slow").flatMap(Double.init).map { min(1, max(0.02, $0)) } ?? 1
    }
}

// Busy, high-contrast stand-in for a desktop so glass presets and opacity differences are visible in captures.
struct DebugBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.62, blue: 0.35), Color(red: 0.27, green: 0.45, blue: 0.85), Color(red: 0.12, green: 0.14, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<14, id: \.self) { index in
                    Text("The quick brown fox jumps over the lazy dog \(index)")
                        .font(.system(size: 15, weight: index.isMultiple(of: 3) ? .bold : .regular))
                        .foregroundStyle(index.isMultiple(of: 2) ? Color.white : Color.black)
                }
            }
            .rotationEffect(.degrees(-8))
        }
    }
}
