import OrbitCore
import SwiftUI

// The panel never takes key status for playback, so a search field first asks the host for keyboard input and
// focuses itself once the panel has actually become key. It hands key status back when it goes away.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var focusOnAppear = false
    // Takes focus whenever the panel is already key, without asking for key status itself, so typing filters
    // straight away once the user has opened Orbit.
    var focusesWhenKey = false
    // A query is on its way; shown in the field so results that stay on screen meanwhile are not mistaken for it.
    var isBusy = false
    var onSubmit: () -> Void = {}
    // Up and Down Arrow move the list selection below the field while the caret stays in it.
    var onMove: ((Int) -> Void)?
    // Called for Escape on an empty field, so the screen can step back instead of only clearing.
    var onEscape: (() -> Void)?

    @Environment(PanelState.self) private var panel
    @Environment(\.panelHost) private var host
    @Environment(\.orbitTheme) private var theme
    @FocusState private var isFocused: Bool
    @State private var wantsFocus = false

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                .foregroundStyle(.secondary)
            // An explicit prompt style, because the plain field's default placeholder all but vanishes on glass.
            TextField(text: $text, prompt: Text(prompt).foregroundStyle(.secondary)) { Text(prompt) }
                .textFieldStyle(.plain)
                .font(OrbitTokens.Typography.body)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: escape)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
            if isBusy, !text.isEmpty {
                ProgressView()
                    .controlSize(.mini)
                    .transition(.opacity)
                    .accessibilityLabel("Searching")
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: OrbitTokens.Icon.regular))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs)
        .frame(height: OrbitTokens.Size.fieldHeight)
        .background {
            RoundedRectangle(cornerRadius: OrbitTokens.Radius.field, style: .continuous)
                .fill(OrbitPalette.quietFill(contrast: theme.contrast))
        }
        .overlay {
            RoundedRectangle(cornerRadius: OrbitTokens.Radius.field, style: .continuous)
                .strokeBorder(theme.accent.opacity(isFocused ? 0.85 : 0), lineWidth: 1.5)
        }
        .overlay {
            if !panel.isKeyWindow {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: requestFocus)
            }
        }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isFocused)
        .animation(theme.animation(OrbitTokens.Motion.hover), value: text.isEmpty)
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isBusy)
        .onAppear {
            if focusOnAppear {
                requestFocus()
            } else if focusesWhenKey, panel.isKeyWindow {
                isFocused = true
            }
        }
        .onChange(of: panel.isKeyWindow) { _, isKey in
            if isKey, wantsFocus || focusesWhenKey { isFocused = true }
            if !isKey {
                wantsFocus = false
                isFocused = false
            }
        }
        .onDisappear {
            if isFocused || wantsFocus { host?.setAcceptsKeyboardInput(false) }
        }
    }

    private func requestFocus() {
        if panel.isKeyWindow {
            isFocused = true
        } else {
            wantsFocus = true
            host?.setAcceptsKeyboardInput(true)
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard let onMove else { return .ignored }
        onMove(offset)
        return .handled
    }

    private func escape() {
        if !text.isEmpty {
            text = ""
            return
        }
        isFocused = false
        host?.setAcceptsKeyboardInput(false)
        onEscape?()
    }
}
