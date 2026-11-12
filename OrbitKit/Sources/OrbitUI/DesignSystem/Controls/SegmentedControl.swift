import SwiftUI

struct Segment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String

    var id: Value { value }
}

// Segmented navigation whose selection highlight slides between segments. `showsTitles` false gives an
// icon-only strip with the titles kept for VoiceOver and tooltips.
struct SegmentedControl<Value: Hashable>: View {
    let segments: [Segment<Value>]
    @Binding var selection: Value
    var showsTitles = true

    @Namespace private var highlight
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.xxs) {
            ForEach(segments) { segment in
                SegmentButton(
                    segment: segment,
                    isSelected: segment.value == selection,
                    showsTitle: showsTitles,
                    highlight: highlight
                ) {
                    withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { selection = segment.value }
                }
            }
        }
        .padding(OrbitTokens.Spacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: OrbitTokens.Radius.segment + 2, style: .continuous)
                .fill(OrbitPalette.quietFill(contrast: theme.contrast))
        }
    }
}

private struct SegmentButton<Value: Hashable>: View {
    let segment: Segment<Value>
    let isSelected: Bool
    let showsTitle: Bool
    let highlight: Namespace.ID
    let action: () -> Void

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showsTitle {
                    // A navigation label never truncates: the glyph gives way first, then the title would.
                    ViewThatFits(in: .horizontal) {
                        Label(segment.title, systemImage: segment.symbol)
                            .labelStyle(SegmentLabelStyle())
                            .fixedSize()
                        Text(segment.title)
                            .fixedSize()
                        Image(systemName: segment.symbol)
                            .font(.system(size: OrbitTokens.Icon.regular, weight: .medium))
                    }
                } else {
                    Image(systemName: segment.symbol)
                        .font(.system(size: OrbitTokens.Icon.regular, weight: .medium))
                }
            }
            .font(OrbitTokens.Typography.segment)
            .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: OrbitTokens.Size.segmentHeight - OrbitTokens.Spacing.xxs * 2)
            .background {
                let shape = RoundedRectangle(cornerRadius: OrbitTokens.Radius.segment, style: .continuous)
                if isSelected {
                    shape
                        .fill(theme.accent.opacity(theme.isHighContrast ? 0.32 : 0.2))
                        .matchedGeometryEffect(id: "selection", in: highlight)
                } else if isHovered {
                    shape.fill(OrbitPalette.hoverFill(contrast: theme.contrast))
                }
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: OrbitTokens.Radius.segment, style: .continuous)
                        .strokeBorder(theme.accent, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
        .help(segment.title)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SegmentLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            configuration.icon.font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
            configuration.title.lineLimit(1)
        }
    }
}
