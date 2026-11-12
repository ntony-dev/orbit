import SwiftUI

// A line too long for its space fades out at the trailing edge instead of ending in an ellipsis, so a long title
// reads as running under the edge of the glass rather than being cut short. Text that fits is left untouched.
struct FadingTruncation: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .horizontal) {
            content
                .fixedSize(horizontal: true, vertical: false)
            content
                .fixedSize(horizontal: true, vertical: false)
                // A zero minimum lets the frame take the offered width instead of growing to the text's.
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        // Long and eased, so the last two or three letters dissolve; a short linear ramp reads
                        // as a hard clip mid-letter.
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.55), location: 0.45),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                            .frame(width: OrbitTokens.Size.truncationFade)
                    }
                }
        }
    }
}

extension View {
    func fadingTruncation() -> some View {
        modifier(FadingTruncation())
    }
}
