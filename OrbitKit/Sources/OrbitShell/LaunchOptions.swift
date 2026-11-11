import CoreGraphics
import OrbitCore

// Launch arguments. `--demo` swaps in OrbitMocks. The rest exist so agents and tests can put the UI into a known
// state and screenshot it without synthesising any user input:
//   --expanded               start with the panel expanded
//   --panel-anchor X,Y       pin the pill's anchored corner to X,Y in AppKit screen coordinates (origin at the
//                            bottom-left of the main display); the canvas grows from there toward screen centre
//   --appearance light|dark  force an appearance for this run without touching Preferences
struct LaunchOptions {
    var usesMocks = false
    var startsExpanded = false
    var anchorPoint: CGPoint?
    var appearance: AppearanceMode?

    init(arguments: [String]) {
        usesMocks = arguments.contains("--demo")
        startsExpanded = arguments.contains("--expanded")
        if let value = Self.value(after: "--panel-anchor", in: arguments) {
            let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { anchorPoint = CGPoint(x: parts[0], y: parts[1]) }
        }
        appearance = Self.value(after: "--appearance", in: arguments).flatMap(AppearanceMode.init(rawValue:))
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
