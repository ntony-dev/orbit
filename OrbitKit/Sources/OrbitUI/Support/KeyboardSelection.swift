import OrbitCore
import SwiftUI

// Arrow-key selection over the rows a list shows, by row key in display order. Kept pure so the movement rules
// are unit tested without a keyboard.
struct KeyboardSelection: Equatable {
    private(set) var key: String?

    // Down from nothing starts at the top and up from nothing at the bottom; the ends do not wrap, as in Finder.
    mutating func move(_ offset: Int, in keys: [String]) {
        guard !keys.isEmpty else {
            key = nil
            return
        }
        guard let key, let index = keys.firstIndex(of: key) else {
            self.key = offset >= 0 ? keys.first : keys.last
            return
        }
        self.key = keys[min(max(index + offset, 0), keys.count - 1)]
    }

    // A filter or reload that hides the selected row drops the selection rather than moving it somewhere unseen.
    mutating func reconcile(with keys: [String]) {
        if let key, !keys.contains(key) { self.key = nil }
    }

    mutating func clear() {
        key = nil
    }

    // The row Return acts on: the selection, or with `fallsBackToFirst` (a filtered list) the top match.
    func target(in keys: [String], fallsBackToFirst: Bool) -> String? {
        if let key, keys.contains(key) { return key }
        return fallsBackToFirst ? keys.first : nil
    }
}

// The highlight for the keyboard selection: the hover fill plus the accent ring used for focus elsewhere, so it
// reads as "where Return goes" and stays distinct from the current playlist's tint.
private struct KeyboardSelectedRow: ViewModifier {
    let isSelected: Bool

    @Environment(\.orbitTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: OrbitTokens.Radius.row, style: .continuous)
                        .fill(OrbitPalette.hoverFill(contrast: theme.contrast))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: OrbitTokens.Radius.row, style: .continuous)
                        .strokeBorder(theme.accent.opacity(theme.isHighContrast ? 1 : 0.7), lineWidth: 1.5)
                }
            }
            .animation(theme.animation(OrbitTokens.Motion.selection), value: isSelected)
    }
}

// Arrow keys, Return and Right Arrow for a list without a text field. The list takes focus whenever the panel
// is key, which only happens once the user has opened Orbit, so it never pulls focus from another app.
private struct KeyboardListNavigation: ViewModifier {
    @Binding var selection: KeyboardSelection
    let keys: [String]
    let onActivate: (String) -> Void
    var onOpen: ((String) -> Void)?

    @Environment(PanelState.self) private var panel
    @Environment(PanelNavigator.self) private var navigator
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { if panel.isKeyWindow { isFocused = true } }
            .onChange(of: panel.isKeyWindow) { _, isKey in isFocused = isKey }
            .onChange(of: keys) { _, keys in selection.reconcile(with: keys) }
            .onKeyPress(phases: [.down, .repeat], action: handle)
    }

    // Takes only the list's share of the panel's key routing; Space, Escape, Left from a track list and the rest
    // go on to the panel.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let context = PanelKeyContext(screen: navigator.keyScreen, hasSelection: selection.key != nil)
        switch PanelKeyRouter.action(for: press.key, modifiers: press.modifiers, in: context) {
        case .moveSelection(let offset):
            guard !keys.isEmpty else { return .ignored }
            selection.move(offset, in: keys)
            return .handled
        case .activateSelection where press.phase == .down:
            guard let key = selection.target(in: keys, fallsBackToFirst: false) else { return .ignored }
            onActivate(key)
            return .handled
        case .openSelection where press.phase == .down:
            guard let onOpen, let key = selection.target(in: keys, fallsBackToFirst: false) else { return .ignored }
            onOpen(key)
            return .handled
        default:
            return .ignored
        }
    }
}

extension View {
    func keyboardSelected(_ isSelected: Bool) -> some View {
        modifier(KeyboardSelectedRow(isSelected: isSelected))
    }

    func keyboardList(
        selection: Binding<KeyboardSelection>,
        keys: [String],
        onActivate: @escaping (String) -> Void,
        onOpen: ((String) -> Void)? = nil
    ) -> some View {
        modifier(KeyboardListNavigation(selection: selection, keys: keys, onActivate: onActivate, onOpen: onOpen))
    }
}
