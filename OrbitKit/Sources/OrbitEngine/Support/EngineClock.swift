import Foundation

// Time as the engine sees it, injected so tests can step through timeouts, backoff and sync intervals.
public struct EngineClock: Sendable {
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(now: @escaping @Sendable () -> Date, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let system = EngineClock(now: { .now }, sleep: { try await Task.sleep(for: $0) })
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
