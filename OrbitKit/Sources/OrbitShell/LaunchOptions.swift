import CoreGraphics
import OrbitCore

// Launch arguments. `--demo` swaps in OrbitMocks and a throwaway settings store. The rest exist so agents and
// tests can put the UI into a known state and screenshot it without synthesising any user input:
//   --expanded               start with the panel expanded (without taking keyboard focus)
//   --panel-anchor X,Y       pin the pill's anchored corner to X,Y in AppKit screen coordinates (origin at the
//                            bottom-left of the main display); the canvas grows from there toward screen centre
//   --appearance light|dark  force an appearance for this run without touching Preferences
//   --settings [PANE]        open Settings behind all other windows, without activating Orbit, against the
//                            right edge of the --panel-anchor's display; PANE is appearance, behavior,
//                            spotify or shortcuts
//   --ui-scenario NAME       Debug builds, with --demo: run the whole app against that OrbitMocks DemoScenario
//   --paused, --pill-hidden  with --demo: start with the simulated playback paused, or with the pill hidden, so
//                            idle cost can be measured in those states (they never touch the real Spotify or
//                            the user's settings)
//   --panel-anchor-kind K    Debug builds, with --panel-anchor: pin that anchor instead of the nearest corner;
//                            K is top, bottom, leading, trailing (an edge's middle) or a corner such as
//                            top-trailing, so edge-centred growth can be captured away from the screen's centre
//   --dock-top-center        Debug builds, with --demo: start with top-centre docking on
//   --morph-every SECONDS    Debug builds: expand and collapse on that period without ever taking keyboard
//                            focus, so the morph and the window frame can be captured frame by frame
// OrbitUI reads its own Debug-only --ui-* arguments for screens and looks; this shell owns every store.
struct LaunchOptions {
    var usesMocks = false
    var startsExpanded = false
    var anchorPoint: CGPoint?
    var appearance: AppearanceMode?
    var settingsPane: SettingsPane?
    var demoScenario: String?
    var startsPaused = false
    var startsWithPillHidden = false
    var pinnedAnchor: PanelAnchor?
    var docksAtTopCenter = false
    var morphPeriod: Duration?

    init(arguments: [String]) {
        usesMocks = arguments.contains("--demo")
        startsExpanded = arguments.contains("--expanded")
        if let value = Self.value(after: "--panel-anchor", in: arguments) {
            let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { anchorPoint = CGPoint(x: parts[0], y: parts[1]) }
        }
        appearance = Self.value(after: "--appearance", in: arguments).flatMap(AppearanceMode.init(rawValue:))
        if arguments.contains("--settings") {
            settingsPane = Self.value(after: "--settings", in: arguments).flatMap(SettingsPane.init(rawValue:)) ?? .appearance
        }
        startsPaused = usesMocks && arguments.contains("--paused")
        startsWithPillHidden = usesMocks && arguments.contains("--pill-hidden")
        #if DEBUG
        if usesMocks { demoScenario = Self.value(after: "--ui-scenario", in: arguments) }
        pinnedAnchor = Self.value(after: "--panel-anchor-kind", in: arguments).flatMap(PanelAnchor.init(debugName:))
        docksAtTopCenter = usesMocks && arguments.contains("--dock-top-center")
        if let seconds = Self.value(after: "--morph-every", in: arguments).flatMap(Double.init), seconds > 0 {
            morphPeriod = .milliseconds(Int(seconds * 1000))
        }
        #endif
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

#if DEBUG
extension PanelAnchor {
    init?(debugName: String) {
        let parts = debugName.split(separator: "-").map(String.init)
        var horizontal = PanelAnchor.Horizontal.center
        var vertical = PanelAnchor.Vertical.center
        for part in parts {
            switch part {
            case "top": vertical = .top
            case "bottom": vertical = .bottom
            case "leading": horizontal = .leading
            case "trailing": horizontal = .trailing
            default: return nil
            }
        }
        guard parts.count == 1 || parts.count == 2, horizontal != .center || vertical != .center else { return nil }
        self.init(horizontal: horizontal, vertical: vertical)
    }
}
#endif
