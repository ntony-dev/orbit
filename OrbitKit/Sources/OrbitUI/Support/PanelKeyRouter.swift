import OrbitCore
import OrbitEngine
import SwiftUI

// Spotify's own desktop shortcuts, so Orbit answers to what Spotify users already know: Space plays or pauses,
// arrows seek, Command-arrows change track and volume.
enum PlayerKeyCommand: Equatable {
    case togglePlayback
    case seek(by: TimeInterval)
    case previousTrack
    case nextTrack
    case changeVolume(by: Int)

    static let seekStep: TimeInterval = 10
    static let volumeStep = 10

    static func command(for key: KeyEquivalent, modifiers: EventModifiers) -> PlayerKeyCommand? {
        guard KeyModifiers(modifiers).isPlainOrCommand else { return nil }
        let command = modifiers.contains(.command)
        switch key {
        case .space where !command: return .togglePlayback
        case .leftArrow: return command ? .previousTrack : .seek(by: -seekStep)
        case .rightArrow: return command ? .nextTrack : .seek(by: seekStep)
        case .upArrow where command: return .changeVolume(by: volumeStep)
        case .downArrow where command: return .changeVolume(by: -volumeStep)
        default: return nil
        }
    }

    @MainActor
    func perform(on playback: PlaybackCoordinator) {
        let snapshot = playback.snapshot
        switch self {
        case .togglePlayback:
            guard snapshot.track != nil, snapshot.allows(snapshot.isPlaying ? .pause : .resume) else { return }
            Task { await playback.togglePlayPause() }
        case .seek(let delta):
            guard let duration = snapshot.track?.duration, snapshot.allows(.seek) else { return }
            let target = min(duration, max(0, snapshot.position(at: .now) + delta))
            Task { await playback.seek(to: target) }
        case .previousTrack:
            guard snapshot.allows(.skipPrevious) else { return }
            Task { await playback.previous() }
        case .nextTrack:
            guard snapshot.allows(.skipNext) else { return }
            Task { await playback.next() }
        case .changeVolume(let delta):
            guard let volume = snapshot.volume, snapshot.allows(.setVolume) else { return }
            Task { await playback.setVolume(volume + delta) }
        }
    }
}

// AppKit also flags arrow keys as keypad and function keys, so modifiers are judged by exclusion.
private struct KeyModifiers {
    let modifiers: EventModifiers

    init(_ modifiers: EventModifiers) {
        self.modifiers = modifiers
    }

    var isPlain: Bool { modifiers.isDisjoint(with: [.command, .shift, .option, .control]) }
    var isPlainOrCommand: Bool { modifiers.isDisjoint(with: [.shift, .option, .control]) }
    var isCommandOnly: Bool { isPlainOrCommand && modifiers.contains(.command) }
}

// What the expanded panel shows, as far as keys are concerned: the player owns plain arrows for seeking, a list
// owns them for its selection, and other screens (devices, the queue) own neither.
enum PanelKeyScreen: Equatable {
    case player
    case list
    case other
}

enum TextFieldFocus: Equatable {
    case empty
    case filled
}

struct PanelKeyContext: Equatable {
    var screen: PanelKeyScreen
    // The focused search or filter field, if any.
    var field: TextFieldFocus?
}

enum PanelKeyAction: Equatable {
    // The focused field types or moves its caret; nothing else may take the key.
    case textEditing
    case moveSelection(by: Int)
    case activateSelection
    case openSelection
    case clearField
    case playback(PlayerKeyCommand)
    case dismissLayer
    case openSettings
    case ignored

    // Which handler performs the action. Each level asks the same router and acts only on its own kind, so a key
    // is never taken by two levels whichever order SwiftUI offers it to them.
    enum Owner {
        case field, list, panel, nobody
    }

    var owner: Owner {
        switch self {
        case .textEditing, .clearField: .field
        case .moveSelection, .activateSelection, .openSelection: .list
        case .playback, .dismissLayer, .openSettings: .panel
        case .ignored: .nobody
        }
    }
}

// The one place that decides what a key does in the expanded panel. In order: Command-comma opens Settings from
// anywhere; Escape clears a field with text, otherwise steps back a layer (which collapses from the player);
// a list's plain Up, Down and Return move and play its selection, with or without its field focused; every other
// key in a focused field is typing; and only then the playback shortcuts, where plain Left and Right seek on the
// player alone, so they never seek from a list.
enum PanelKeyRouter {
    static func action(for key: KeyEquivalent, modifiers: EventModifiers, in context: PanelKeyContext) -> PanelKeyAction {
        let flags = KeyModifiers(modifiers)
        if key == ",", flags.isCommandOnly { return .openSettings }
        if key == .escape, flags.isPlain {
            return context.field == .filled ? .clearField : .dismissLayer
        }
        if context.screen == .list, flags.isPlain {
            switch key {
            case .downArrow: return .moveSelection(by: 1)
            case .upArrow: return .moveSelection(by: -1)
            case .return: return .activateSelection
            case .rightArrow where context.field == nil: return .openSelection
            default: break
            }
        }
        if context.field != nil { return .textEditing }
        guard let command = PlayerKeyCommand.command(for: key, modifiers: modifiers) else { return .ignored }
        if case .seek = command, context.screen != .player { return .ignored }
        return .playback(command)
    }
}

// Performs the panel's own share of the router's decisions for every screen. It sits on the expanded surface,
// above whatever holds focus, so it sees each key the focused field or list leaves alone.
struct PanelKeyboard: ViewModifier {
    @Environment(PanelNavigator.self) private var navigator
    @Environment(PanelState.self) private var panel
    @Environment(PlaybackCoordinator.self) private var playback

    func body(content: Content) -> some View {
        content.onKeyPress(phases: [.down, .repeat]) { press in
            let context = PanelKeyContext(screen: navigator.keyScreen, field: navigator.textFieldFocus)
            let action = PanelKeyRouter.action(for: press.key, modifiers: press.modifiers, in: context)
            guard action.owner == .panel else { return .ignored }
            // Holding a key repeats seeking, skipping and volume, but never toggles, steps back or reopens.
            if press.phase == .repeat {
                guard case .playback(let command) = action, command != .togglePlayback else { return .handled }
            }
            switch action {
            case .playback(let command): command.perform(on: playback)
            case .dismissLayer: panel.dismissActiveLayer()
            case .openSettings: OrbitSettings.open()
            default: break
            }
            return .handled
        }
    }
}

// An invisible focus target for screens with no field or list, so the panel's shortcuts (Space above all) work
// as soon as the screen appears. It is a sibling of the controls rather than their container, because a focused
// container would make every button inside it report focus and draw its ring. Focus is only claimed while the
// panel is key, which happens only once the user has opened Orbit.
struct PanelKeyFocusTarget: ViewModifier {
    @Environment(PanelState.self) private var panel
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content.background {
            Color.clear
                .focusable(interactions: .edit)
                .focused($isFocused)
                .focusEffectDisabled()
                .accessibilityHidden(true)
                .onAppear { if panel.isKeyWindow { isFocused = true } }
                .onChange(of: panel.isKeyWindow) { _, isKey in if isKey { isFocused = true } }
        }
    }
}

extension View {
    func panelKeyFocusTarget() -> some View {
        modifier(PanelKeyFocusTarget())
    }
}
