import SwiftUI

// A thin track that thickens and shows a knob on hover or drag. Used for seeking and volume. The value is a
// fraction in 0...1; the caller owns what it means and decides when to commit.
struct OrbitSlider: View {
    let value: Double
    var onScrub: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void
    var accessibilityLabel: String
    var accessibilityValue: String
    var step: Double = 0.05

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var dragValue: Double?

    private var isActive: Bool { isEnabled && (isHovered || dragValue != nil) }
    private var displayed: Double { min(1, max(0, dragValue ?? value)) }

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
                    .frame(width: knob, height: knob)
                    .offset(x: min(max(0, width * displayed - knob / 2), width - knob))
                    .scaleEffect(isActive ? 1 : 0.4)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(height: proxy.size.height)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(1, max(0, gesture.location.x / max(1, width)))
                        dragValue = fraction
                        onScrub(fraction)
                    }
                    .onEnded { gesture in
                        let fraction = min(1, max(0, gesture.location.x / max(1, width)))
                        onCommit(fraction)
                        dragValue = nil
                    },
                isEnabled: isEnabled
            )
        }
        .frame(height: OrbitTokens.Size.sliderHitHeight)
        .onHover { hovering in isHovered = hovering }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isActive)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCommit(min(1, value + step))
            case .decrement: onCommit(max(0, value - step))
            @unknown default: break
            }
        }
    }
}
