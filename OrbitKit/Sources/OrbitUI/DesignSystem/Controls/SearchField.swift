import OrbitCore
import SwiftUI

// The panel never takes key status for playback, so a search field first asks the host for keyboard input and
// focuses itself once the panel has actually become key. It hands key status back when it goes away.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var focusOnAppear = false
    var onSubmit: () -> Void = {}
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
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(OrbitTokens.Typography.body)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: escape)
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
        .onAppear {
            if focusOnAppear { requestFocus() }
        }
        .onChange(of: panel.isKeyWindow) { _, isKey in
            if isKey, wantsFocus { isFocused = true }
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
