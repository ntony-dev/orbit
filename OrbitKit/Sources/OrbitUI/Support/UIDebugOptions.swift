import Foundation
import OrbitCore
import SwiftUI

// Debug-only launch arguments that put the UI into a known state for screenshots without simulated input, and
// without writing to the user's Preferences:
//   --ui-screen player|picker|library|liked|queue|search|devices|playlist:<id>
//   --ui-query <text>              the library search query, so search results can be captured
//   --ui-hover                     show the pill's hover controls
//   --ui-scenario <name>           with --demo only, read by the shell, which builds the scenario's stores:
//                                  signed-out, automation-denied, automation-not-asked,
//                                  automation-not-asked-playing, spotify-closed, idle, paused, rate-limited,
//                                  empty-library, switch-fails
//   --ui-glass clear|balanced|tinted, --ui-opacity 0...1, --ui-accent neutral|mint|ice|amber|lavender,
//   --ui-pill compact|regular, --ui-no-artwork
//   --ui-reduce-transparency, --ui-increase-contrast, --ui-reduce-motion
//   --ui-tour                      visit picker, library and player, then collapse, on a timer; pair it with
//                                  --expanded, since expanding from the pill makes the panel key
//   --ui-slow <factor>             play every animation at this speed (0.1 is ten times slower)
//   --ui-switch <playlist-id>      two seconds after launch, switch to that playlist without collapsing
//   --ui-shelf                     with --demo only, pin two playlists and add three recents, so the picker's
//                                  sections can be captured (the demo keeps no shelf file)
//   --ui-backdrop [gradient|bright|busy|plain]
//                                  draw a stand-in desktop inside the canvas, because a capture of Orbit's
//                                  window alone cannot include what the glass refracts from behind it: a
//                                  colored gradient (the default), a white page, a dense, high-contrast mix, or
//                                  a calm wallpaper with no text or shapes, toned to the appearance, for
//                                  public screenshots
struct UIDebugOptions {
    var screen: String?
    var searchQuery: String?
    var forcesPillHover = false
    var glassPreset: GlassPreset?
    var backgroundOpacity: Double?
    var accent: AccentChoice?
    var pillSize: PillSize?
    var hidesArtwork = false
    var reducesTransparency = false
    var increasesContrast = false
    var reducesMotion = false
    var backdrop: DebugBackdrop.Style?
    var runsTour = false
    var switchPlaylistID: String?
    var seedsShelf = false
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
        searchQuery = value("--ui-query")
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
        if arguments.contains("--ui-backdrop") {
            backdrop = value("--ui-backdrop").flatMap(DebugBackdrop.Style.init(rawValue:)) ?? .gradient
        }
        runsTour = arguments.contains("--ui-tour")
        switchPlaylistID = value("--ui-switch")
        seedsShelf = arguments.contains("--ui-shelf") && arguments.contains("--demo")
        animationSpeed = value("--ui-slow").flatMap(Double.init).map { min(1, max(0.02, $0)) } ?? 1
    }
}

// Stand-ins for a desktop, so glass presets, opacity and text legibility can be judged in captures: a colored
// gradient, a white document page (the hardest case for light text and light glass), a dense mix of photos,
// icons and black and white text (the hardest case for reading anything at all), and a plain wallpaper whose
// lettering-free tones cannot be mistaken for a rendering fault in published screenshots.
struct DebugBackdrop: View {
    enum Style: String {
        case gradient, bright, busy, plain
    }

    let style: Style
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch style {
        case .gradient: gradient
        case .bright: bright
        case .busy: busy
        case .plain: plain
        }
    }

    // Soft color fields blended over a diagonal base, so the glass has varied tone to refract but no edges.
    private var plain: some View {
        let isDark = colorScheme == .dark
        let base: [Color] = isDark
            ? [Color(red: 0.13, green: 0.16, blue: 0.27), Color(red: 0.20, green: 0.17, blue: 0.30), Color(red: 0.08, green: 0.18, blue: 0.22)]
            : [Color(red: 0.86, green: 0.89, blue: 0.96), Color(red: 0.94, green: 0.88, blue: 0.90), Color(red: 0.86, green: 0.93, blue: 0.91)]
        let glows: [(Color, UnitPoint)] = isDark
            ? [(Color(red: 0.36, green: 0.30, blue: 0.62), .topLeading), (Color(red: 0.14, green: 0.42, blue: 0.48), .bottomTrailing), (Color(red: 0.52, green: 0.28, blue: 0.40), .trailing)]
            : [(Color(red: 0.70, green: 0.78, blue: 0.97), .topLeading), (Color(red: 0.98, green: 0.80, blue: 0.74), .bottomTrailing), (Color(red: 0.78, green: 0.90, blue: 0.84), .trailing)]
        return GeometryReader { proxy in
            let radius = max(proxy.size.width, proxy.size.height) * 0.75
            ZStack {
                LinearGradient(colors: base, startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(glows.indices, id: \.self) { index in
                    RadialGradient(colors: [glows[index].0.opacity(0.85), glows[index].0.opacity(0)], center: glows[index].1, startRadius: 0, endRadius: radius)
                }
            }
        }
    }

    private var gradient: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.62, blue: 0.35), Color(red: 0.27, green: 0.45, blue: 0.85), Color(red: 0.12, green: 0.14, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            sampleText(count: 14, size: 15, colors: [.white, .black])
                .rotationEffect(.degrees(-8))
        }
    }

    private var bright: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            VStack(alignment: .leading, spacing: 9) {
                ForEach(0..<24, id: \.self) { index in
                    if index.isMultiple(of: 7) {
                        Text("Heading \(index / 7 + 1)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(white: 0.1))
                    } else {
                        Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \(index)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.25))
                    }
                }
            }
            .padding(24)
        }
    }

    private var busy: some View {
        let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown, .white, .black]
        return ZStack {
            Color(white: 0.5)
            Canvas { context, size in
                var generator = SplitMix(seed: 7)
                for _ in 0..<160 {
                    let rect = CGRect(
                        x: generator.next(in: -40...size.width),
                        y: generator.next(in: -40...size.height),
                        width: generator.next(in: 12...90),
                        height: generator.next(in: 12...90)
                    )
                    let color = colors[Int(generator.next(in: 0...Double(colors.count - 1)).rounded())]
                    let shape = generator.next(in: 0...1) < 0.5 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 6)
                    context.fill(shape, with: .color(color.opacity(generator.next(in: 0.6...1))))
                }
            }
            sampleText(count: 30, size: 12, colors: [.white, .black, .yellow])
                .rotationEffect(.degrees(4))
        }
    }

    private func sampleText(count: Int, size: CGFloat, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: size * 0.6) {
            ForEach(0..<count, id: \.self) { index in
                Text("The quick brown fox jumps over the lazy dog \(index)")
                    .font(.system(size: size, weight: index.isMultiple(of: 3) ? .bold : .regular))
                    .foregroundStyle(colors[index % colors.count])
            }
        }
    }
}

// A fixed sequence, so the busy backdrop is the same in every capture.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return range.lowerBound + Double(z >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
