import SwiftUI

// What a fitted list tells the panel: where it starts in the expanded surface and how tall its content is.
// Neither depends on the surface's own height, so fitting the surface to them can never feed back on itself.
struct ListFit: Equatable {
    var top: CGFloat
    var content: CGFloat
    // Set by the library on each tab's list, so an outgoing tab's list never sizes the surface for the new one.
    var libraryTab: LibraryTab?

    var screenHeight: CGFloat { top + content }
}

struct ListFitKey: PreferenceKey {
    static let defaultValue: [ListFit] = []

    static func reduce(value: inout [ListFit], nextValue: () -> [ListFit]) {
        value += nextValue()
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    static var expandedSurface: NamedCoordinateSpace { .named("orbit.expanded-surface") }
}

// Every scrolling list in the panel. It reports its natural height so the surface can fit it, never draws a
// scroller (a legacy, always-visible scroller would run a dark track down the glass), and fades whichever edge
// has more content beyond it, so a row cut by the edge reads as continuing rather than broken.
struct PanelScroll<Content: View>: View {
    // Scrolled into view whenever it changes: the keyboard selection, or the current track on arrival.
    var reveal: AnyHashable?
    var revealAnchor: UnitPoint?
    @ViewBuilder let content: Content

    @Environment(\.orbitTheme) private var theme
    @State private var contentHeight: CGFloat = 0
    @State private var top: CGFloat = 0
    @State private var edges = ScrollEdges(fadesTop: false, fadesBottom: false)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            // A section appearing above (a new pin) stays in view instead of pushing the list's top out of sight.
            .defaultScrollAnchor(.top, for: .sizeChanges)
            .onScrollGeometryChange(for: ScrollEdges.self, of: ScrollEdges.init) { _, new in
                withAnimation(theme.animation(OrbitTokens.Motion.hover)) { edges = new }
            }
            .mask { EdgeFadeMask(edges: edges) }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .expandedSurface).minY } action: { top = $0 }
            .preference(key: ListFitKey.self, value: contentHeight > 0 ? [ListFit(top: top, content: contentHeight)] : [])
            .onAppear {
                guard let reveal else { return }
                proxy.scrollTo(reveal, anchor: revealAnchor)
            }
            .onChange(of: reveal) { _, target in
                guard let target else { return }
                withAnimation(theme.animation(OrbitTokens.Motion.selection)) { proxy.scrollTo(target, anchor: revealAnchor) }
            }
        }
    }
}

struct ScrollEdges: Equatable {
    var fadesTop: Bool
    var fadesBottom: Bool

    init(fadesTop: Bool, fadesBottom: Bool) {
        self.fadesTop = fadesTop
        self.fadesBottom = fadesBottom
    }

    init(_ geometry: ScrollGeometry) {
        let visible = geometry.visibleRect
        fadesTop = visible.minY > 1
        fadesBottom = visible.maxY < geometry.contentSize.height - 1
    }
}

private struct EdgeFadeMask: View {
    let edges: ScrollEdges

    var body: some View {
        let fade = OrbitTokens.Size.listEdgeFade
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(edges.fadesTop ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(edges.fadesBottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
    }
}

// Empty, loading and error states inside a fitted list keep a sensible minimum, centred in it.
extension View {
    func listState() -> some View {
        frame(maxWidth: .infinity, minHeight: OrbitTokens.Size.listStateHeight)
    }
}
