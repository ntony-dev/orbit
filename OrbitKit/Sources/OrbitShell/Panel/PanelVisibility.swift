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

// What the fullscreen rule needs to know about one display, read on the main actor before the window list is.
struct FullscreenContext: Equatable, Sendable {
    // Quartz global coordinates, like WindowSnapshot.bounds.
    var displayBounds: CGRect
    // How far below the display's top edge a full screen window may start: the camera housing on displays with
    // a notch, or the menu bar when the user keeps it shown in full screen. Zero otherwise.
    var fullscreenTopInset: CGFloat
    // With the menu bar set to hide on the desktop, an ordinary zoomed window can cover the whole display.
    var menuBarAutoHidesOnDesktop: Bool
    // The active app, when the system reports its presentation as full screen.
    var frontmostFullscreenPID: pid_t?
}

enum FullscreenDetection {
    // Two independent signals, because neither alone covers every setup:
    // - The active app is in full screen (NSApp.currentSystemPresentationOptions) and one of its windows spans
    //   this display, allowing for a notch or a menu bar kept visible above it.
    // - Some ordinary-level window covers the whole display, menu bar strip included, which no regular window
    //   can do unless the menu bar auto-hides on the desktop. This catches a full screen app on a display other
    //   than the active one, and borderless full-display windows.
    static func isCovered(_ context: FullscreenContext, by windows: [WindowSnapshot], excluding ownPID: pid_t) -> Bool {
        let display = context.displayBounds
        return windows.contains { window in
            guard window.ownerPID != ownPID, window.layer == 0, window.alpha > 0 else { return false }
            let bounds = window.bounds
            let spansWidth = abs(bounds.minX - display.minX) <= 1 && abs(bounds.width - display.width) <= 1
            let reachesBottom = abs(bounds.maxY - display.maxY) <= 1
            guard spansWidth, reachesBottom else { return false }
            let topGap = bounds.minY - display.minY
            if window.ownerPID == context.frontmostFullscreenPID {
                return topGap >= -1 && topGap <= context.fullscreenTopInset + 1
            }
            return abs(topGap) <= 1 && !context.menuBarAutoHidesOnDesktop
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
