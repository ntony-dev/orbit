public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system, light, dark
}

// Native glass has only regular and clear variants; these presets combine them with an Orbit-drawn backing and tint.
public enum GlassPreset: String, CaseIterable, Codable, Sendable {
    case clear, balanced, tinted
}

public enum PillSize: String, CaseIterable, Codable, Sendable {
    case compact, regular
}

// sRGB components in 0...1, kept free of AppKit/SwiftUI so OrbitCore stays UI-agnostic.
public struct RGBColor: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum AccentChoice: Hashable, Codable, Sendable {
    case neutral, mint, ice, amber, lavender
    case custom(RGBColor)

    public static let presets: [AccentChoice] = [.neutral, .mint, .ice, .amber, .lavender]
}

public struct DeviceReference: Hashable, Codable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// The pill's centre in unit coordinates of a display's visible frame, so it survives resolution changes.
public struct SavedPanelPosition: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
