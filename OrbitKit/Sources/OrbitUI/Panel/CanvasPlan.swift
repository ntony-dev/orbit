import CoreGraphics

// The canvas must contain the surface for the whole animation. It grows to the union of the old and new
// surface before anything moves and shrinks to the new surface only once the animation has settled.
enum CanvasPlan {
    static func canvas(for surface: CGSize) -> CGSize {
        OrbitTokens.Size.canvas(for: surface)
    }

    // Canvas to apply right away when the surface heads for `target` while `current` is allocated.
    static func during(current: CGSize, target: CGSize) -> CGSize {
        let needed = canvas(for: target)
        return CGSize(width: max(current.width, needed.width), height: max(current.height, needed.height))
    }

    // Canvas to apply after settling, or nil when the canvas already fits.
    static func after(current: CGSize, target: CGSize) -> CGSize? {
        let needed = canvas(for: target)
        return current == needed ? nil : needed
    }
}
