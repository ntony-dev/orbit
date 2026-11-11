import SwiftUI

// Shows artwork at exactly the pixel size it occupies. A cached image appears in the first frame; anything else
// fades in over a quiet placeholder. With `keepsPrevious`, the old image stays until the new one is decoded, so a
// track change cross-fades instead of flashing the placeholder.
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = OrbitTokens.Radius.artwork
    var placeholderSymbol = "music.note"
    var keepsPrevious = false

    @Environment(\.displayScale) private var displayScale
    @Environment(\.orbitTheme) private var theme
    @State private var shown: Shown?

    private struct Shown: Equatable {
        let url: URL
        let image: CGImage

        static func == (lhs: Shown, rhs: Shown) -> Bool { lhs.url == rhs.url && lhs.image === rhs.image }
    }

    init(
        url: URL?,
        size: CGFloat,
        cornerRadius: CGFloat = OrbitTokens.Radius.artwork,
        placeholderSymbol: String = "music.note",
        keepsPrevious: Bool = false
    ) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        self.placeholderSymbol = placeholderSymbol
        self.keepsPrevious = keepsPrevious
        if let url, let cached = ArtworkPipeline.shared.memory[ArtworkKey(url: url, pixelSize: Self.pixels(size, scale: 2))] {
            _shown = State(initialValue: Shown(url: url, image: cached.image))
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(OrbitPalette.quietFill(contrast: theme.contrast))
            Image(systemName: placeholderSymbol)
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(.tertiary)
            if let visible {
                Image(decorative: visible.image, scale: displayScale)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .id(visible.url)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            // A hairline keeps light artwork from bleeding into light glass.
            shape.strokeBorder(.primary.opacity(theme.isHighContrast ? 0.25 : 0.07), lineWidth: 0.5)
        }
        .task(id: TaskKey(url: url, scale: displayScale)) {
            await load()
        }
        .accessibilityHidden(true)
    }

    private var visible: Shown? {
        guard let shown else { return nil }
        return keepsPrevious || shown.url == url ? shown : nil
    }

    private struct TaskKey: Equatable {
        let url: URL?
        let scale: CGFloat
    }

    private func load() async {
        guard let url else {
            shown = nil
            return
        }
        if shown?.url == url { return }
        let key = ArtworkKey(url: url, pixelSize: Self.pixels(size, scale: displayScale))
        if let cached = ArtworkPipeline.shared.memory[key] {
            shown = Shown(url: url, image: cached.image)
            return
        }
        guard let artwork = await ArtworkPipeline.shared.artwork(for: key), !Task.isCancelled else { return }
        withAnimation(theme.animation(OrbitTokens.Motion.content)) {
            shown = Shown(url: url, image: artwork.image)
        }
    }

    static func pixels(_ points: CGFloat, scale: CGFloat) -> Int {
        Int((points * scale).rounded(.up))
    }
}
