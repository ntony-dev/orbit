import AppKit
import CoreServices
import OrbitCore

// Sends Apple events to one target app on a private serial queue: sending blocks until Spotify replies, and the
// queue keeps commands in the order they were issued. Events are addressed by process ID, never bundle ID, so an
// event can never launch an app that has quit in the meantime.
final class AppleEventChannel: Sendable {
    private let bundleIdentifier: String
    private let queue: DispatchQueue
    private let timeout: TimeInterval

    init(bundleIdentifier: String, timeout: TimeInterval = 3) {
        self.bundleIdentifier = bundleIdentifier
        self.timeout = timeout
        queue = DispatchQueue(label: "app.orbit.automation.\(bundleIdentifier)", qos: .userInitiated)
    }

    func isRunning() -> Bool {
        runningProcessID() != nil
    }

    private func runningProcessID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { !$0.isTerminated }?
            .processIdentifier
    }

    func permission(prompting: Bool) async -> AutomationPermission {
        await perform { channel in channel.determinePermission(prompting: prompting) }
    }

    func send(_ event: SpotifyAppleEvent) async throws(OrbitError) -> AppleEventReply {
        try await perform { channel in channel.sendNow(event) }.get()
    }

    // Runs several reads back to back on the queue so no command can interleave between them.
    func batch<Value: Sendable>(
        _ body: @escaping @Sendable (_ send: (SpotifyAppleEvent) -> Result<AppleEventReply, OrbitError>) -> Result<Value, OrbitError>
    ) async throws(OrbitError) -> Value {
        try await perform { channel in body(channel.sendNow) }.get()
    }

    private func perform<Value: Sendable>(_ body: @escaping @Sendable (AppleEventChannel) -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body(self)) }
        }
    }

    private func determinePermission(prompting: Bool) -> AutomationPermission {
        guard let pid = runningProcessID() else { return .requiresSpotifyRunning }
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        guard let address = target.aeDesc else { return .notDetermined }
        let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, prompting)
        return switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(procNotFound): .requiresSpotifyRunning
        default: .notDetermined
        }
    }

    private func sendNow(_ event: SpotifyAppleEvent) -> Result<AppleEventReply, OrbitError> {
        guard let pid = runningProcessID() else { return .failure(.spotifyNotRunning) }
        let descriptor = event.descriptor(target: NSAppleEventDescriptor(processIdentifier: pid))
        do {
            let reply = try descriptor.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
            if let code = reply.paramDescriptor(forKeyword: SpotifyAppleEvent.Code.errorNumber)?.int32Value, code != noErr {
                return .failure(Self.error(for: code))
            }
            return .success(AppleEventReply(reply.paramDescriptor(forKeyword: SpotifyAppleEvent.Code.directObject)))
        } catch let error as NSError {
            return .failure(Self.error(for: Int32(truncatingIfNeeded: error.code)))
        }
    }

    static func error(for status: Int32) -> OrbitError {
        switch Int(status) {
        case errAEEventNotPermitted, errAEEventWouldRequireUserConsent: .automationDenied
        case procNotFound, connectionInvalid: .spotifyNotRunning
        case errAETimeout: .unexpected(detail: "Spotify didn't answer in time.")
        default: .unexpected(detail: "Apple event error \(status)")
        }
    }
}

// NSAppleEventDescriptor is not Sendable, so replies cross the queue boundary as plain values.
struct AppleEventReply: Sendable {
    let string: String?
    let integer: Int?
    let appProperties: SpotifyAppProperties?

    init(_ descriptor: NSAppleEventDescriptor?) {
        guard let descriptor, descriptor.descriptorType != fourCharCode("null") else {
            string = nil
            integer = nil
            appProperties = nil
            return
        }
        string = descriptor.stringValue
        integer = descriptor.coerce(toDescriptorType: fourCharCode("long")).map { Int($0.int32Value) }
        appProperties = descriptor.descriptorType == fourCharCode("reco") ? SpotifyAppProperties(record: descriptor) : nil
    }
}
