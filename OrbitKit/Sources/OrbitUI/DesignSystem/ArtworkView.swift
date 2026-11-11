import SwiftUI

struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat = OrbitTokens.Radius.artwork

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                OrbitTokens.Palette.track
                    .overlay(Image(systemName: "music.note").foregroundStyle(OrbitTokens.Palette.secondaryText))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }
}
