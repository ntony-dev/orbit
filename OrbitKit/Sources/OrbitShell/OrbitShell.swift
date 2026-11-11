import AppKit

public enum OrbitShell {
    @MainActor
    public static func run(arguments: [String] = CommandLine.arguments) {
        let app = NSApplication.shared
        let delegate = AppDelegate(options: LaunchOptions(arguments: arguments))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) { app.run() }
    }
}
