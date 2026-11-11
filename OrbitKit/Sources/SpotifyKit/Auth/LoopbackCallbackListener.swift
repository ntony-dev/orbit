import Foundation
import Network
import OrbitCore
import Synchronization

// A one-shot HTTP listener bound to 127.0.0.1 only. It answers the first request for `path`, then shuts down.
struct LoopbackCallbackListener: Sendable {
    let port: UInt16
    let path: String
    let timeout: Duration

    // `whenReady` runs once the socket is accepting, so the browser can never race ahead of the listener.
    // `handle` decides the outcome of the callback request and therefore which page the browser shows.
    func receive<Value: Sendable>(
        whenReady: @escaping @Sendable () async throws(OrbitError) -> Void,
        handle: @escaping @Sendable (URLComponents) -> Result<Value, OrbitError>
    ) async throws(OrbitError) -> Value {
        let session = CallbackSession(listener: self, whenReady: whenReady, handle: handle)
        let result = await withTaskCancellationHandler {
            await session.run()
        } onCancel: {
            session.finish(.failure(.cancelled))
        }
        return try result.get()
    }
}

private final class CallbackSession<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Result<Value, OrbitError>, Never>?
        var outcome: Result<Value, OrbitError>?
        var isFinished = false
        var listener: NWListener?
        var timer: Task<Void, Never>?
    }

    private static var maximumRequestSize: Int { 16 * 1024 }

    private let configuration: LoopbackCallbackListener
    private let whenReady: @Sendable () async throws(OrbitError) -> Void
    private let handle: @Sendable (URLComponents) -> Result<Value, OrbitError>
    private let queue = DispatchQueue(label: "SpotifyKit.LoopbackCallbackListener")
    private let state = Mutex(State())

    init(
        listener: LoopbackCallbackListener,
        whenReady: @escaping @Sendable () async throws(OrbitError) -> Void,
        handle: @escaping @Sendable (URLComponents) -> Result<Value, OrbitError>
    ) {
        configuration = listener
        self.whenReady = whenReady
        self.handle = handle
    }

    func run() async -> Result<Value, OrbitError> {
        await withCheckedContinuation { continuation in
            let early = state.withLock { state -> Result<Value, OrbitError>? in
                if let outcome = state.outcome { return outcome }
                state.continuation = continuation
                return nil
            }
            if let early {
                continuation.resume(returning: early)
            } else {
                start()
            }
        }
    }

    func finish(_ outcome: Result<Value, OrbitError>) {
        let resolved = state.withLock { state -> (CheckedContinuation<Result<Value, OrbitError>, Never>?, NWListener?, Task<Void, Never>?)? in
            guard !state.isFinished else { return nil }
            state.isFinished = true
            let continuation = state.continuation
            state.continuation = nil
            if continuation == nil { state.outcome = outcome }
            defer {
                state.listener = nil
                state.timer = nil
            }
            return (continuation, state.listener, state.timer)
        }
        guard let (continuation, listener, timer) = resolved else { return }
        listener?.cancel()
        timer?.cancel()
        continuation?.resume(returning: outcome)
    }

    private func start() {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            finish(.failure(.unexpected(detail: "Invalid callback port.")))
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = false

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            finish(.failure(Self.listenerError(error, port: configuration.port)))
            return
        }
        let proceed = state.withLock { state -> Bool in
            guard !state.isFinished else { return false }
            state.listener = listener
            state.timer = Task { [weak self, timeout = configuration.timeout] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(.unexpected(detail: "Timed out waiting for Spotify sign-in.")))
            }
            return true
        }
        guard proceed else { return }

        listener.stateUpdateHandler = { [weak self] newState in
            self?.listenerChanged(to: newState)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        listener.start(queue: queue)
    }

    private func listenerChanged(to newState: NWListener.State) {
        switch newState {
        case .ready:
            // Deliberately not cancelled when the session ends: it may be the very request delivering the callback.
            Task { [weak self, whenReady] in
                do throws(OrbitError) {
                    try await whenReady()
                } catch {
                    self?.finish(.failure(error))
                }
            }
        case .failed(let error), .waiting(let error):
            finish(.failure(Self.listenerError(error, port: configuration.port)))
        default:
            break
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumRequestSize) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let head = Self.requestHead(in: buffer) {
                respond(to: head, on: connection)
            } else if error != nil || isComplete || buffer.count >= Self.maximumRequestSize {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let parts = head.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, parts[0] == "GET",
              let components = URLComponents(string: "http://127.0.0.1\(parts[1])"),
              components.path == configuration.path
        else {
            send(CallbackPage.notFound, on: connection, then: nil)
            return
        }
        let isFinished = state.withLock { $0.isFinished }
        guard !isFinished else {
            send(CallbackPage.failure, on: connection, then: nil)
            return
        }
        let outcome = handle(components)
        let page: CallbackPage
        switch outcome {
        case .success: page = .success
        case .failure: page = .failure
        }
        send(page, on: connection) { [weak self] in self?.finish(outcome) }
    }

    private func send(_ page: CallbackPage, on connection: NWConnection, then completion: (@Sendable () -> Void)?) {
        connection.send(content: page.response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
            completion?()
        })
    }

    private static func requestHead(in buffer: Data) -> String? {
        guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
        return head.split(separator: "\r\n", maxSplits: 1).first.map(String.init)
    }

    private static func listenerError(_ error: any Error, port: UInt16) -> OrbitError {
        if let error = error as? NWError, case .posix(let code) = error, code == .EADDRINUSE {
            return .callbackPortInUse(port: Int(port))
        }
        return .network(detail: "The sign-in listener couldn't start.")
    }
}

private enum CallbackPage {
    case success, failure, notFound

    var response: Data {
        let status = self == .notFound ? "404 Not Found" : "200 OK"
        let body = Data(html.utf8)
        // No-store and no-referrer keep the authorization code in the URL out of caches and outgoing requests.
        let head = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Referrer-Policy: no-referrer",
            "Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'",
            "Connection: close",
            "", "",
        ].joined(separator: "\r\n")
        return Data(head.utf8) + body
    }

    private var html: String {
        let (title, detail) = switch self {
        case .success: ("You're signed in to Orbit.", "You can close this tab.")
        case .failure: ("Sign-in didn't finish.", "You can close this tab and try again from Orbit.")
        case .notFound: ("Not found.", "")
        }
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Orbit</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>:root{color-scheme:light dark}body{font:15px -apple-system,system-ui,sans-serif;display:grid;place-items:center;min-height:90vh;margin:0}main{text-align:center}h1{font-size:20px;font-weight:600;margin:0 0 6px}p{margin:0;opacity:.7}</style>
        </head><body><main><h1>\(title)</h1><p>\(detail)</p></main></body></html>
        """
    }
}
