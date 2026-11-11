// The canvas corner (or top edge centre) that holds the pill. The shell keeps it fixed on screen while the canvas
// resizes, so the expanded surface grows away from it: a pill near the bottom-right of a screen is anchored
// bottom-trailing and grows up and to the left.
public struct PanelAnchor: Hashable, Codable, Sendable {
    public enum Horizontal: String, Hashable, Codable, Sendable {
        case leading, center, trailing
    }

    public enum Vertical: String, Hashable, Codable, Sendable {
        case top, bottom
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
    public static let bottomLeading = PanelAnchor(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = PanelAnchor(horizontal: .trailing, vertical: .bottom)
}
