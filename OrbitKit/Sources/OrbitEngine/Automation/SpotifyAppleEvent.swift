import Foundation
import OrbitCore

func fourCharCode(_ code: String) -> FourCharCode {
    code.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
}

// Spotify's scripting surface as raw Apple events, built from the codes in Spotify.sdef. Raw events avoid
// compiling AppleScript source and need no osascript subprocess.
enum SpotifyAppleEvent: Hashable, Sendable {
    case appProperties
    case trackProperty(TrackProperty)
    case play, pause, playPause, nextTrack, previousTrack
    case playTrack(SpotifyURI, context: SpotifyURI?)
    case setPosition(TimeInterval)
    case setVolume(Int)
    case setShuffling(Bool)
    case setRepeating(Bool)

    enum TrackProperty: String, Sendable {
        case id = "ID  "
        case name = "pnam"
        case artist = "pArt"
        case album = "pAlb"
        case duration = "pDur"
        case artworkURL = "aUrl"
    }

    enum Code {
        static let spotifySuite = fourCharCode("spfy")
        static let coreSuite = fourCharCode("core")
        static let getData = fourCharCode("getd")
        static let setData = fourCharCode("setd")
        static let directObject = fourCharCode("----")
        static let data = fourCharCode("data")
        static let context = fourCharCode("cotx")
        static let objectSpecifier = fourCharCode("obj ")
        static let property = fourCharCode("prop")
        static let desiredClass = fourCharCode("want")
        static let keyForm = fourCharCode("form")
        static let keyData = fourCharCode("seld")
        static let container = fourCharCode("from")
        static let errorNumber = fourCharCode("errn")

        static let allProperties = fourCharCode("pALL")
        static let currentTrack = fourCharCode("pTrk")
        static let soundVolume = fourCharCode("pVol")
        static let playerState = fourCharCode("pPlS")
        static let playerPosition = fourCharCode("pPos")
        static let repeating = fourCharCode("pRep")
        static let shuffling = fourCharCode("pShu")
        // The sdef gives `shuffling enabled` and `repeating enabled` the same code, so only one value is reachable.
        static let controlsEnabled = fourCharCode("pReE")

        static let playing = fourCharCode("kPSP")
        static let paused = fourCharCode("kPSp")
    }

    var eventClass: AEEventClass {
        switch self {
        case .appProperties, .trackProperty, .setPosition, .setVolume, .setShuffling, .setRepeating: Code.coreSuite
        case .play, .pause, .playPause, .nextTrack, .previousTrack, .playTrack: Code.spotifySuite
        }
    }

    var eventID: AEEventID {
        switch self {
        case .appProperties, .trackProperty: Code.getData
        case .setPosition, .setVolume, .setShuffling, .setRepeating: Code.setData
        case .play: fourCharCode("Play")
        case .pause: fourCharCode("Paus")
        case .playPause: fourCharCode("PlPs")
        case .nextTrack: fourCharCode("Next")
        case .previousTrack: fourCharCode("Prev")
        case .playTrack: fourCharCode("PCtx")
        }
    }

    func descriptor(target: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass,
            eventID: eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        switch self {
        case .appProperties:
            event.setParam(Self.property(Code.allProperties), forKeyword: Code.directObject)
        case .trackProperty(let property):
            let track = Self.property(Code.currentTrack)
            event.setParam(Self.property(fourCharCode(property.rawValue), of: track), forKeyword: Code.directObject)
        case .playTrack(let uri, let context):
            event.setParam(NSAppleEventDescriptor(string: uri.rawValue), forKeyword: Code.directObject)
            if let context {
                event.setParam(NSAppleEventDescriptor(string: context.rawValue), forKeyword: Code.context)
            }
        case .setPosition(let seconds):
            Self.set(Code.playerPosition, to: NSAppleEventDescriptor(double: max(0, seconds)), on: event)
        case .setVolume(let percent):
            Self.set(Code.soundVolume, to: NSAppleEventDescriptor(int32: Int32(min(100, max(0, percent)))), on: event)
        case .setShuffling(let enabled):
            Self.set(Code.shuffling, to: NSAppleEventDescriptor(boolean: enabled), on: event)
        case .setRepeating(let enabled):
            Self.set(Code.repeating, to: NSAppleEventDescriptor(boolean: enabled), on: event)
        case .play, .pause, .playPause, .nextTrack, .previousTrack:
            break
        }
        return event
    }

    static func property(_ code: FourCharCode, of container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: Code.objectSpecifier) ?? .record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: Code.property), forKeyword: Code.desiredClass)
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: Code.property), forKeyword: Code.keyForm)
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code), forKeyword: Code.keyData)
        specifier.setDescriptor(container, forKeyword: Code.container)
        return specifier
    }

    private static func set(_ code: FourCharCode, to value: NSAppleEventDescriptor, on event: NSAppleEventDescriptor) {
        event.setParam(property(code), forKeyword: Code.directObject)
        event.setParam(value, forKeyword: Code.data)
    }
}

// The application-level properties, read in a single `get properties` event.
struct SpotifyAppProperties: Hashable, Sendable {
    var status: LocalPlayerState.Status
    var position: TimeInterval?
    var volume: Int?
    var isShuffling: Bool?
    var isRepeating: Bool?
    var controlsEnabled: Bool?

    init?(record: NSAppleEventDescriptor) {
        guard let state = record.forKeyword(SpotifyAppleEvent.Code.playerState) else { return nil }
        status = switch state.enumCodeValue {
        case SpotifyAppleEvent.Code.playing: .playing
        case SpotifyAppleEvent.Code.paused: .paused
        default: .stopped
        }
        position = record.forKeyword(SpotifyAppleEvent.Code.playerPosition).map(\.doubleValue)
        volume = record.forKeyword(SpotifyAppleEvent.Code.soundVolume).map { Int($0.int32Value) }
        isShuffling = record.forKeyword(SpotifyAppleEvent.Code.shuffling).map(\.booleanValue)
        isRepeating = record.forKeyword(SpotifyAppleEvent.Code.repeating).map(\.booleanValue)
        controlsEnabled = record.forKeyword(SpotifyAppleEvent.Code.controlsEnabled).map(\.booleanValue)
    }
}
