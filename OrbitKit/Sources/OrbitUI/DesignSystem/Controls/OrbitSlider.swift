import SwiftUI

// A thin track that thickens and shows a knob on hover, drag or keyboard focus. Used for seeking and volume. The
// value is a fraction in 0...1; the caller owns what it means and decides when to commit. Arrow keys and
// VoiceOver adjust it by `step`, and assistive technologies see a real slider with the caller's spoken value.
struct OrbitSlider: View {
    let value: Double
    var onScrub: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void
    var accessibilityLabel: String
    var accessibilityValue: String
    var step: Double = 0.05

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var dragValue: Double?

    private var isActive: Bool { isEnabled && (isHovered || dragValue != nil || isFocused) }
    private var displayed: Double { clamp(dragValue ?? value) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackHeight = isActive ? OrbitTokens.Size.sliderTrackActive : OrbitTokens.Size.sliderTrack
            let knob = OrbitTokens.Size.sliderKnob
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(OrbitPalette.sliderTrack(contrast: theme.contrast))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(isEnabled ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.tertiary))
                    .frame(width: max(trackHeight, width * displayed), height: trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 0.5)
                    .overlay {
                        if isFocused { Circle().strokeBorder(theme.accent, lineWidth: 2).padding(-3) }
                    }
                    .frame(width: knob, height: knob)
                    // Scaled before it is moved: a scale applied after the offset would scale the offset too and
                    // carry the knob ahead of the pointer while dragging.
                    .scaleEffect(isActive ? (dragValue != nil && !theme.reducesMotion ? 1.15 : 1) : 0.4)
                    .opacity(isActive ? 1 : 0)
                    .offset(x: min(max(0, width * displayed - knob / 2), width - knob))
            }
            .frame(height: proxy.size.height)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = clamp(gesture.location.x / max(1, width))
                        dragValue = fraction
                        onScrub(fraction)
                    }
                    .onEnded { gesture in
                        onCommit(clamp(gesture.location.x / max(1, width)))
                        dragValue = nil
                    },
                isEnabled: isEnabled
            )
        }
        .frame(height: OrbitTokens.Size.sliderHitHeight)
        .onHover { hovering in isHovered = hovering }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isActive)
        .animation(theme.animation(OrbitTokens.Motion.press), value: dragValue != nil)
        // Focusable through keyboard navigation like a system slider, so a mouse drag never leaves a focus ring.
        .focusable(isEnabled, interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            // Command-arrows belong to the panel's track and volume shortcuts.
            guard isEnabled, !press.modifiers.contains(.command) else { return .ignored }
            let direction: Double = press.key == .leftArrow || press.key == .downArrow ? -1 : 1
            onCommit(clamp(value + direction * step))
            return .handled
        }
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { onCommit(clamp($0)) }), in: 0...1, step: step) {
                Text(accessibilityLabel)
            }
            .accessibilityValue(accessibilityValue)
            .disabled(!isEnabled)
        }
    }

    private func clamp(_ fraction: Double) -> Double {
        min(1, max(0, fraction))
    }
}
