import SwiftUI

// A round glyph button: hover and pressed fills, an accent ring for keyboard focus, and an accent glyph plus dot
// when `isOn`, so a toggle's state never depends on color alone. A toggle that is off recedes to the secondary
// style, so with the neutral accent "on" still reads as brighter rather than only as a dot. Toggles draw in one
// flat color: hierarchical rendering paints the whole of `repeat.1` as a secondary layer, so repeat-one looked
// dimmer than repeat-all in the same accent.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = OrbitTokens.Size.iconButton
    var glyphSize: CGFloat = OrbitTokens.Icon.regular
    var isOn = false
    var isToggle = false
    var showsOnIndicator = true
    // A secondary action inside a row recedes like an off toggle until the pointer reaches it.
    var recedesAtRest = false

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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isPanelResizing) private var isPanelResizing
    @State private var isHovered = false
    @State private var isPointerInside = false

    var body: some View {
        configuration.label
            .font(.system(size: style.glyphSize, weight: .semibold))
            .symbolRenderingMode(style.isToggle ? .monochrome : .hierarchical)
            .foregroundStyle(glyphStyle)
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
            .opacity(isEnabled ? 1 : OrbitPalette.disabledOpacity(colorScheme, contrast: theme.contrast))
            // While the panel's window is changing size (a drawer opening), the pointer is reported over buttons it
            // is not on for a frame, which flashed their hover fill. An entry during a resize waits until the panel
            // has settled and shows only if the pointer is still there; leaving always applies at once.
            .onHover { hovering in
                isPointerInside = hovering
                if !hovering || !isPanelResizing { isHovered = hovering && isEnabled }
            }
            .onChange(of: isPanelResizing) { _, isResizing in
                if !isResizing { isHovered = isPointerInside && isEnabled }
            }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .animation(theme.animation(OrbitTokens.Motion.press), value: configuration.isPressed)
            .animation(theme.animation(OrbitTokens.Motion.toggle), value: style.isOn)
    }

    private var glyphStyle: AnyShapeStyle {
        if style.isOn, isEnabled { return AnyShapeStyle(theme.accent) }
        // A disabled glyph dims from the primary color, so an unavailable toggle is not dimmed twice.
        // An off toggle stays receded under the pointer, where the hover fill is its feedback: brightened, one just
        // switched off looked still on until the pointer left.
        if style.isToggle, isEnabled { return AnyShapeStyle(.secondary) }
        if style.recedesAtRest, isEnabled, !isHovered { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(.primary)
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
            .opacity(isEnabled ? 1 : OrbitPalette.disabledRowOpacity(contrast: theme.contrast))
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(OrbitTokens.Typography.captionEmphasized)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, OrbitTokens.Spacing.l)
            .frame(height: OrbitTokens.Size.capsuleButton)
            .foregroundStyle(isProminent ? AnyShapeStyle(OrbitPalette.prominentGlyph) : AnyShapeStyle(.primary))
            .background { Capsule().fill(fill) }
            .overlay {
                if isFocused { Capsule().strokeBorder(theme.accent, lineWidth: 2).padding(-3) }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : OrbitPalette.disabledOpacity(colorScheme, contrast: theme.contrast))
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
    // True from the moment the panel's surface starts changing size until its window has settled around it.
    @Entry var isPanelResizing = false
}

extension View {
    func iconButton(
        diameter: CGFloat = OrbitTokens.Size.iconButton,
        glyph: CGFloat = OrbitTokens.Icon.regular,
        isOn: Bool = false,
        isToggle: Bool = false,
        showsOnIndicator: Bool = true,
        recedesAtRest: Bool = false
    ) -> some View {
        buttonStyle(IconButtonStyle(
            diameter: diameter, glyphSize: glyph, isOn: isOn, isToggle: isToggle,
            showsOnIndicator: showsOnIndicator, recedesAtRest: recedesAtRest
        ))
        .focusEffectDisabled()
    }

    func rowButton(isSelected: Bool = false) -> some View {
        buttonStyle(RowButtonStyle(isSelected: isSelected)).focusEffectDisabled()
    }

    func capsuleButton(prominent: Bool = false) -> some View {
        buttonStyle(CapsuleButtonStyle(isProminent: prominent)).focusEffectDisabled()
    }
}
