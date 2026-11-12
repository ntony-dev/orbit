// The point of the canvas that holds the pill: a corner, or the middle of the screen edge the pill sits on. The
// shell keeps it fixed on screen while the canvas resizes, so the expanded surface grows away from it: a pill near
// the bottom-right of a screen is anchored bottom-trailing and grows up and to the left, and a pill in the middle
// of the top edge is anchored top-centre and grows straight down, evenly to both sides.
public struct PanelAnchor: Hashable, Codable, Sendable {
    public enum Horizontal: String, Hashable, Codable, Sendable {
        case leading, center, trailing
    }

    public enum Vertical: String, Hashable, Codable, Sendable {
        case top, center, bottom
    }

    public var horizontal: Horizontal
    public var vertical: Vertical

    public init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let topLeading = PanelAnchor(horizontal: .leading, vertical: .top)
    public static let topCenter = PanelAnchor(horizontal: .center, vertical: .top)
    public static let topTrailing = PanelAnchor(horizontal: .trailing, vertical: .top)
    public static let centerLeading = PanelAnchor(horizontal: .leading, vertical: .center)
    public static let centerTrailing = PanelAnchor(horizontal: .trailing, vertical: .center)
    public static let bottomLeading = PanelAnchor(horizontal: .leading, vertical: .bottom)
    public static let bottomCenter = PanelAnchor(horizontal: .center, vertical: .bottom)
    public static let bottomTrailing = PanelAnchor(horizontal: .trailing, vertical: .bottom)

    // The four corners and the middles of the four edges; the canvas centre is never an anchor.
    public static let all: [PanelAnchor] = [
        .topLeading, .topCenter, .topTrailing, .centerLeading, .centerTrailing, .bottomLeading, .bottomCenter, .bottomTrailing,
    ]
}
