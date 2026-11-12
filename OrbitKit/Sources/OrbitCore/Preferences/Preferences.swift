import Foundation
import Observation

@MainActor
@Observable
public final class Preferences {
    public var appearance: AppearanceMode { didSet { store(appearance, .appearance) } }
    public var glassPreset: GlassPreset { didSet { store(glassPreset, .glassPreset) } }
    public var backgroundOpacity: Double { didSet { store(backgroundOpacity, .backgroundOpacity) } }
    public var accent: AccentChoice { didSet { store(accent, .accent) } }
    public var pillSize: PillSize { didSet { store(pillSize, .pillSize) } }
    public var showsArtwork: Bool { didSet { store(showsArtwork, .showsArtwork) } }
    public var reducesAnimation: Bool { didSet { store(reducesAnimation, .reducesAnimation) } }
    public var alwaysOnTop: Bool { didSet { store(alwaysOnTop, .alwaysOnTop) } }
    public var isPillVisible: Bool { didSet { store(isPillVisible, .isPillVisible) } }
    public var snapsToEdges: Bool { didSet { store(snapsToEdges, .snapsToEdges) } }
    public var docksAtTopCenter: Bool { didSet { store(docksAtTopCenter, .docksAtTopCenter) } }
    public var remembersPosition: Bool { didSet { store(remembersPosition, .remembersPosition) } }
    // Keyed by display UUID (CGDisplayCreateUUIDFromDisplayID), which stays stable across reconnects.
    public var savedPositions: [String: SavedPanelPosition] { didSet { store(savedPositions, .savedPositions) } }
    // The display the user last placed the pill on, so it returns there when that display reconnects.
    public var panelDisplayID: String? { didSet { store(panelDisplayID, .panelDisplayID) } }
    public var hidesInFullscreen: Bool { didSet { store(hidesInFullscreen, .hidesInFullscreen) } }
    public var hidesWhenSpotifyQuits: Bool { didSet { store(hidesWhenSpotifyQuits, .hidesWhenSpotifyQuits) } }
    public var collapsesAfterAction: Bool { didSet { store(collapsesAfterAction, .collapsesAfterAction) } }
    // Off by default: the open panel stays open, and only gives keyboard focus back, until the user collapses it.
    public var collapsesOnOutsideClick: Bool { didSet { store(collapsesOnOutsideClick, .collapsesOnOutsideClick) } }
    public var syncFrequency: SyncFrequency { didSet { store(syncFrequency, .syncFrequency) } }
    public var preferredDevice: DeviceReference? { didSet { store(preferredDevice, .preferredDevice) } }
    // Takes precedence over the SpotifyClientID Info.plist key when it is not blank.
    public var clientIDOverride: String? { didSet { store(clientIDOverride, .clientIDOverride) } }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Self.load(.appearance, from: defaults) ?? .system
        glassPreset = Self.load(.glassPreset, from: defaults) ?? .balanced
        backgroundOpacity = Self.load(.backgroundOpacity, from: defaults) ?? 0.5
        accent = Self.load(.accent, from: defaults) ?? .neutral
        pillSize = Self.load(.pillSize, from: defaults) ?? .regular
        showsArtwork = Self.load(.showsArtwork, from: defaults) ?? true
        reducesAnimation = Self.load(.reducesAnimation, from: defaults) ?? false
        alwaysOnTop = Self.load(.alwaysOnTop, from: defaults) ?? true
        isPillVisible = Self.load(.isPillVisible, from: defaults) ?? true
        snapsToEdges = Self.load(.snapsToEdges, from: defaults) ?? true
        docksAtTopCenter = Self.load(.docksAtTopCenter, from: defaults) ?? false
        remembersPosition = Self.load(.remembersPosition, from: defaults) ?? true
        savedPositions = Self.load(.savedPositions, from: defaults) ?? [:]
        panelDisplayID = Self.load(.panelDisplayID, from: defaults) ?? nil
        hidesInFullscreen = Self.load(.hidesInFullscreen, from: defaults) ?? true
        hidesWhenSpotifyQuits = Self.load(.hidesWhenSpotifyQuits, from: defaults) ?? false
        collapsesAfterAction = Self.load(.collapsesAfterAction, from: defaults) ?? true
        collapsesOnOutsideClick = Self.load(.collapsesOnOutsideClick, from: defaults) ?? false
        syncFrequency = Self.load(.syncFrequency, from: defaults) ?? .standard
        preferredDevice = Self.load(.preferredDevice, from: defaults) ?? nil
        clientIDOverride = Self.load(.clientIDOverride, from: defaults) ?? nil
    }

    private enum Key: String {
        case appearance, glassPreset, backgroundOpacity, accent, pillSize, showsArtwork, reducesAnimation
        case alwaysOnTop, isPillVisible, snapsToEdges, docksAtTopCenter, remembersPosition, savedPositions, panelDisplayID
        case hidesInFullscreen, hidesWhenSpotifyQuits, collapsesAfterAction, preferredDevice, clientIDOverride
        case syncFrequency, collapsesOnOutsideClick

        var defaultsKey: String { "orbit.preferences.\(rawValue)" }
    }

    // Values are JSON-encoded so enums with payloads and optionals share one storage path.
    private func store<Value: Encodable>(_ value: Value, _ key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.defaultsKey)
    }

    private static func load<Value: Decodable>(_ key: Key, from defaults: UserDefaults) -> Value? {
        guard let data = defaults.data(forKey: key.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
