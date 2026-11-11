import SwiftUI

// A round glyph button: hover and pressed fills, an accent ring for keyboard focus, and an accent glyph plus dot
// when `isOn`, so a toggle's state never depends on color alone.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = OrbitTokens.Size.iconButton
    var glyphSize: CGFloat = OrbitTokens.Icon.regular
    var isOn = false
    var showsOnIndicator = true

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, style: self)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: IconButtonStyle

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: style.glyphSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(style.isOn ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.primary))
            .frame(width: style.diameter, height: style.diameter)
            .background {
                Circle().fill(fill)
            }
            .overlay(alignment: .bottom) {
                if style.isOn, style.showsOnIndicator {
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 3, height: 3)
                        .offset(y: -2)
                }
            }
            .overlay {
                if isFocused {
                    Circle().strokeBorder(theme.accent, lineWidth: 2)
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed && !theme.reducesMotion ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { hovering in isHovered = hovering && isEnabled }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .animation(theme.animation(OrbitTokens.Motion.press), value: configuration.isPressed)
    }

    private var fill: Color {
        if configuration.isPressed { return OrbitPalette.pressedFill(contrast: theme.contrast) }
        if isHovered { return OrbitPalette.hoverFill(contrast: theme.contrast) }
        return .clear
    }
}

// Full-width list rows. Selection uses the accent; hover and press use neutral fills.
struct RowButtonStyle: ButtonStyle {
    var isSelected = false
    var cornerRadius: CGFloat = OrbitTokens.Radius.row

    func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }
}

private struct RowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let cornerRadius: CGFloat

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .background { shape.fill(fill) }
            .overlay {
                if isFocused { shape.strokeBorder(theme.accent, lineWidth: 1.5) }
            }
            .environment(\.isRowHovered, isHovered)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering in isHovered = hovering && isEnabled }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .animation(theme.animation(OrbitTokens.Motion.press), value: configuration.isPressed)
    }

    private var fill: Color {
        if configuration.isPressed { return OrbitPalette.pressedFill(contrast: theme.contrast) }
        if isSelected { return theme.accent.opacity(theme.isHighContrast ? 0.26 : 0.15) }
        if isHovered { return OrbitPalette.hoverFill(contrast: theme.contrast) }
        return .clear
    }
}

// Text actions such as "Connect Spotify" or "Try Again". The prominent variant is a solid label-color capsule,
// which stays neutral in both appearances instead of borrowing the accent.
struct CapsuleButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, isProminent: isProminent)
    }
}

private struct CapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isProminent: Bool

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(OrbitTokens.Typography.captionEmphasized)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, OrbitTokens.Spacing.l)
            .frame(height: 26)
            .foregroundStyle(isProminent ? AnyShapeStyle(OrbitPalette.prominentGlyph) : AnyShapeStyle(.primary))
            .background { Capsule().fill(fill) }
            .overlay {
                if isFocused { Capsule().strokeBorder(theme.accent, lineWidth: 2).padding(-3) }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !theme.reducesMotion ? 0.97 : 1)
            .onHover { hovering in isHovered = hovering && isEnabled }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .animation(theme.animation(OrbitTokens.Motion.press), value: configuration.isPressed)
    }

    private var fill: Color {
        if isProminent {
            return OrbitPalette.prominentFill.opacity(configuration.isPressed ? 0.72 : (isHovered ? 0.86 : 1))
        }
        if configuration.isPressed { return OrbitPalette.pressedFill(contrast: theme.contrast) }
        return isHovered ? OrbitPalette.pressedFill(contrast: theme.contrast) : OrbitPalette.hoverFill(contrast: theme.contrast)
    }
}

extension EnvironmentValues {
    // Lets row content reveal secondary actions (play glyph, pin) only while the pointer is over the row.
    @Entry var isRowHovered = false
}

extension View {
    func iconButton(
        diameter: CGFloat = OrbitTokens.Size.iconButton,
        glyph: CGFloat = OrbitTokens.Icon.regular,
        isOn: Bool = false,
        showsOnIndicator: Bool = true
    ) -> some View {
        buttonStyle(IconButtonStyle(diameter: diameter, glyphSize: glyph, isOn: isOn, showsOnIndicator: showsOnIndicator))
            .focusEffectDisabled()
    }

    func rowButton(isSelected: Bool = false) -> some View {
        buttonStyle(RowButtonStyle(isSelected: isSelected)).focusEffectDisabled()
    }

    func capsuleButton(prominent: Bool = false) -> some View {
        buttonStyle(CapsuleButtonStyle(isProminent: prominent)).focusEffectDisabled()
    }
}
