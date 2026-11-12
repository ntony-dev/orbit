import KeyboardShortcuts

enum ShortcutAction: String, CaseIterable, Sendable {
    // The raw value names the stored shortcut, so the library's keeps the picker's name and a combination
    // recorded before the picker joined the library still works.
    case toggleOrbit, focusSearch, togglePlayback, nextTrack, previousTrack
    case openLibrary = "openPlaylistPicker"

    var title: String {
        switch self {
        case .toggleOrbit: "Open or close Orbit"
        case .focusSearch: "Search"
        case .togglePlayback: "Play or pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .openLibrary: "Open Library"
        }
    }
}

// Global shortcuts are Carbon hot keys registered by KeyboardShortcuts: they need no Input Monitoring permission
// and fire only for combinations the user assigned, so nothing is registered until the user records one.
// KeyboardShortcuts always stores in UserDefaults.standard, so demo runs use their own names to keep the user's
// real shortcuts from being read, registered twice or overwritten.
@MainActor
final class GlobalShortcuts {
    private let namePrefix: String
    private var listeners: [Task<Void, Never>] = []

    init(isDemo: Bool) {
        namePrefix = isDemo ? "orbit.demo." : "orbit."
    }

    func name(for action: ShortcutAction) -> KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(namePrefix + action.rawValue)
    }

    func start(perform: @escaping @MainActor (ShortcutAction) -> Void) {
        guard listeners.isEmpty else { return }
        for action in ShortcutAction.allCases {
            let presses = KeyboardShortcuts.events(.keyDown, for: name(for: action))
            listeners.append(Task {
                for await _ in presses {
                    perform(action)
                }
            })
        }
    }
}
