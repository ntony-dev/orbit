import SwiftUI

struct Segment<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String

    var id: Value { value }
}

// The panel's section navigation. It has no track of its own, so it reads as part of the glass rather than a
// control laid on top of it; only the active segment carries a surface, a small piece of native glass that
// slides across to the next segment when the selection changes.
struct SegmentedControl<Value: Hashable>: View {
    let segments: [Segment<Value>]
    @Binding var selection: Value

    @Namespace private var highlight
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.xs) {
            ForEach(segments) { segment in
                SegmentButton(segment: segment, isSelected: segment.value == selection) {
                    withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { selection = segment.value }
                }
            }
        }
        .background { highlightTrack }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    // One highlight that is never removed, only moved: it takes the frame of the selected slot in a row of empty
    // slots laid out like the segments. Swapping glass between segments would hand the move to the glass morph,
    // which drops out while the whole surface is also resizing; a single piece of glass simply follows its frame.
    // It sits beneath the labels, so they never become glass content.
    private var highlightTrack: some View {
        ZStack {
            HStack(spacing: OrbitTokens.Spacing.xs) {
                ForEach(segments) { segment in
                    Color.clear.matchedGeometryEffect(id: segment.value, in: highlight)
                }
            }
            selectionSurface
                .matchedGeometryEffect(id: selection, in: highlight, isSource: false)
        }
    }

    // Glass is the highlight only while the panel itself is glass; with Reduce Transparency the panel is nearly
    // opaque and a second translucent layer would read as a smudge, so a flat accent fill takes its place.
    @ViewBuilder
    private var selectionSurface: some View {
        if theme.reducesTransparency {
            Capsule()
                .fill(OrbitPalette.selectionFill(accent: theme.accent, contrast: theme.contrast))
                .overlay { Capsule().strokeBorder(OrbitPalette.selectionStroke(contrast: theme.contrast), lineWidth: 1) }
        } else {
            // The contrast outline is the glass's own content, so it is drawn on the glass rather than under it.
            Capsule()
                .strokeBorder(OrbitPalette.selectionStroke(contrast: theme.contrast), lineWidth: theme.isHighContrast ? 1 : 0)
                .glassEffect(.regular.tint(OrbitPalette.selectionTint(accent: theme.accent)), in: Capsule())
        }
    }
}

private struct SegmentButton<Value: Hashable>: View {
    let segment: Segment<Value>
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.orbitTheme) private var theme
    @Environment(\.isFocused) private var isFocused
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            // A navigation label never truncates: the glyph gives way first, then the title would.
            ViewThatFits(in: .horizontal) {
                Label(segment.title, systemImage: segment.symbol)
                    .labelStyle(SegmentLabelStyle(iconStyle: isSelected ? AnyShapeStyle(theme.accent) : foreground))
                    .fixedSize()
                Text(segment.title)
                    .fixedSize()
                Image(systemName: segment.symbol)
                    .font(.system(size: OrbitTokens.Icon.regular, weight: .medium))
            }
            .font(OrbitTokens.Typography.segment)
            .foregroundStyle(foreground)
            // Text otherwise animates a style change as a content transition, which drops the glyphs for most of
            // a move while the surface around them is resizing.
            .contentTransition(.identity)
            .frame(maxWidth: .infinity)
            .frame(height: OrbitTokens.Size.segmentHeight)
            .overlay {
                if isFocused {
                    Capsule().strokeBorder(theme.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered = $0 }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
        .help(segment.title)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // Hover lifts an inactive label toward the active one instead of giving it a surface, so only the selection
    // ever sits on the glass.
    private var foreground: AnyShapeStyle {
        isSelected || isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }
}

// The active glyph takes the accent, so a chosen accent shows in the navigation without tinting its text.
private struct SegmentLabelStyle: LabelStyle {
    let iconStyle: AnyShapeStyle

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            configuration.icon
                .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                .foregroundStyle(iconStyle)
            configuration.title.lineLimit(1)
        }
    }
}
