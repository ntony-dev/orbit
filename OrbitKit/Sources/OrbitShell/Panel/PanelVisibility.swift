import CoreGraphics
import Foundation
import OrbitEngine

struct PanelVisibility: Equatable, Sendable {
    var isPillVisible: Bool
    var hidesInFullscreen: Bool
    var isFullscreenAppFrontmost: Bool
    var hidesWhenSpotifyQuits: Bool
    var isSpotifyRunning: Bool
    // The user opened Orbit from the menu bar or a shortcut while the pill would otherwise be hidden; it stays up
    // until that expansion collapses.
    var isPresentedOnDemand: Bool

    var showsPanel: Bool {
        if isPresentedOnDemand { return true }
        guard isPillVisible else { return false }
        if hidesInFullscreen, isFullscreenAppFrontmost { return false }
        if hidesWhenSpotifyQuits, !isSpotifyRunning { return false }
        return true
    }
}

extension InterfaceVisibility {
    init(isPanelVisible: Bool, isExpanded: Bool, areScreensAsleep: Bool) {
        if !isPanelVisible || areScreensAsleep {
            self = .hidden
        } else {
            self = isExpanded ? .expanded : .collapsed
        }
    }
}

// A window as the window server reports it. Bounds are in Quartz global coordinates (origin at the top-left of the
// main display, y down), the same space as CGDisplayBounds. Reading these needs no Screen Recording permission.
struct WindowSnapshot: Equatable, Sendable {
    var ownerPID: pid_t
    var layer: Int
    var bounds: CGRect
    var alpha: Double
}

enum FullscreenDetection {
    // A full screen app, in its own Space or as a borderless full-display window, puts an ordinary-level window
    // exactly over the display, menu bar area included, which no regular window can do.
    static func isCovered(displayBounds: CGRect, by windows: [WindowSnapshot], excluding ownPID: pid_t) -> Bool {
        windows.contains { window in
            window.ownerPID != ownPID
                && window.layer == 0
                && window.alpha > 0
                && abs(window.bounds.minX - displayBounds.minX) <= 1
                && abs(window.bounds.minY - displayBounds.minY) <= 1
                && abs(window.bounds.width - displayBounds.width) <= 1
                && abs(window.bounds.height - displayBounds.height) <= 1
        }
    }

    static func onScreenWindows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { return nil }
            return WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds, alpha: entry[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
