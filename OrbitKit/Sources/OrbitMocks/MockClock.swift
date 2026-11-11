import Foundation
import Synchronization

// A clock that only moves when told to, so tests can step through timeouts, backoff and sync intervals.
public final class MockClock: Sendable {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Date
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let state: Mutex<State>

    public init(start: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        state = Mutex(State(now: start))
    }

    public var now: @Sendable () -> Date {
        { [self] in state.withLock { $0.now } }
    }

    public var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in try await sleep(for: duration) }
    }

    public var pendingSleepers: Int {
        state.withLock { $0.sleepers.count }
    }

    public func sleep(for duration: Duration) async throws {
        let id = UUID()
        let (seconds, attoseconds) = duration.components
        let interval = TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let resumeNow = state.withLock { state -> Bool in
                    if Task.isCancelled { return true }
                    let deadline = state.now.addingTimeInterval(interval)
                    if interval <= 0 { return true }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
    }

    public func advance(by seconds: TimeInterval) {
        let due = state.withLock { state -> [Sleeper] in
            state.now.addTimeInterval(seconds)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            for id in due.keys { state.sleepers.removeValue(forKey: id) }
            return due.values.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}
