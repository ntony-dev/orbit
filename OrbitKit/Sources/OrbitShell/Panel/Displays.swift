import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    // The UUID stays the same across reconnects, sleep and resolution changes, unlike the display ID.
    var displayUUID: String? {
        guard let displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var layout: DisplayLayout? {
        displayUUID.map { DisplayLayout(id: $0, visibleFrame: visibleFrame) }
    }

    // The first screen is the one with the menu bar, which placement uses as its fallback.
    static var layouts: [DisplayLayout] {
        screens.compactMap(\.layout)
    }

    static func screen(for layout: DisplayLayout) -> NSScreen? {
        screens.first { $0.displayUUID == layout.id }
    }
}
