import Darwin
import Foundation
import OrbitCore
@testable import SpotifyKit
import Synchronization

final class StubTransport: HTTPTransport {
    typealias Handler = @Sendable (URLRequest) async throws(OrbitError) -> (Data, HTTPURLResponse)

    private let handler: Handler
    private let log = Mutex<[URLRequest]>([])

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] { log.withLock { $0 } }
    var apiRequests: [URLRequest] { requests.filter { $0.url?.host == "api.spotify.com" } }
    var tokenRequests: [URLRequest] { requests.filter { $0.url == SpotifyAccounts.tokenURL } }

    func send(_ request: URLRequest) async throws(OrbitError) -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        return try await handler(request)
    }
}

final class InMemoryTokenStore: TokenStore {
    private let stored: Mutex<StoredSession?>

    init(_ session: StoredSession? = nil) {
        stored = Mutex(session)
    }

    var session: StoredSession? { stored.withLock { $0 } }

    func load() throws(OrbitError) -> StoredSession? { stored.withLock { $0 } }
    func save(_ session: StoredSession) throws(OrbitError) { stored.withLock { $0 = session } }
    func delete() throws(OrbitError) { stored.withLock { $0 = nil } }
}

final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = Mutex(start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

enum HTTP {
    static func response(_ request: URLRequest, status: Int = 200, json: String = "", headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
    }

    static func tokenJSON(access: String, refresh: String? = nil, expiresIn: Int = 3600, scope: String = SpotifyAccounts.scopes.joined(separator: " ")) -> String {
        let refreshField = refresh.map { #","refresh_token":"\#($0)""# } ?? ""
        return #"{"access_token":"\#(access)","token_type":"Bearer","expires_in":\#(expiresIn),"scope":"\#(scope)"\#(refreshField)}"#
    }

    static func formFields(_ request: URLRequest) -> [String: String] {
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }

    static func query(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    static func jsonBody(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }
}

enum Sessions {
    static func valid(clock: TestClock, access: String = "access-1", refresh: String = "refresh-1", expiresIn: TimeInterval = 3600) -> StoredSession {
        StoredSession(
            id: UUID(),
            clientID: "client-123",
            accessToken: access,
            refreshToken: refresh,
            expiresAt: clock.now.addingTimeInterval(expiresIn),
            scopes: SpotifyAccounts.scopes
        )
    }
}

enum LocalPorts {
    // Below macOS's ephemeral range (49152...65535), so no outgoing connection elsewhere in the suite can take a
    // planned listener port as its source port, and well away from 8888 and a real sign-in.
    private static let band: Range<UInt16> = 20_000..<40_000
    private static let next = Mutex<UInt16>(UInt16.random(in: 20_000..<30_000))

    // Every call gets a distinct port that was bindable at that moment, so parallel tests never share one.
    static func free() -> UInt16 {
        while true {
            let port = next.withLock { current -> UInt16 in
                let port = current
                current = current + 1 < band.upperBound ? current + 1 : band.lowerBound
                return port
            }
            if isBindable(port) { return port }
        }
    }

    private static func isBindable(_ port: UInt16) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        return withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, length) }
        } == 0
    }

    // Holds a port open on 127.0.0.1 the way another app would, to exercise the port-in-use path.
    final class Occupier: Sendable {
        let socket: Int32
        let port: UInt16

        init() {
            let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = 0
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
            }
            _ = listen(descriptor, 1)
            _ = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
            }
            socket = descriptor
            port = UInt16(bigEndian: address.sin_port)
        }

        deinit { close(socket) }
    }
}

enum LocalHTTP {
    // A plain loopback GET, standing in for the browser following Spotify's redirect.
    static func get(_ url: URL) async throws -> (status: Int, body: String) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }
}

// Answers every connection on 127.0.0.1 with one fixed response and records what it was sent.
final class CannedHTTPServer: Sendable {
    private let occupier = LocalPorts.Occupier()
    private let received = Locked<[String]>([])
    private let stopped = Locked(false)

    var port: UInt16 { occupier.port }

    init(response: String) {
        let reply = Array(response.utf8)
        let thread = Thread { [occupier, received, stopped] in
            while !stopped.value {
                var waiting = pollfd(fd: occupier.socket, events: Int16(POLLIN), revents: 0)
                guard poll(&waiting, 1, 50) > 0 else { continue }
                let client = accept(occupier.socket, nil, nil)
                guard client >= 0 else { continue }
                var buffer = [UInt8](repeating: 0, count: 64 * 1024)
                let count = recv(client, &buffer, buffer.count, 0)
                received.set(received.value + [String(decoding: buffer.prefix(max(count, 0)), as: UTF8.self)])
                _ = reply.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
                close(client)
            }
        }
        thread.start()
    }

    var requests: [String] { received.value }

    // The thread holds the Occupier, so the socket closes once the accept loop notices and exits.
    deinit { stopped.set(true) }
}

// Plain BSD sockets, for what URLSession can't do: hold a silent connection open, or dial a specific address.
final class RawConnection: Sendable {
    private let descriptor: Int32

    // nil when the connection is refused.
    init?(ipv4 address: String, port: UInt16) {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        var target = sockaddr_in()
        target.sin_family = sa_family_t(AF_INET)
        target.sin_addr.s_addr = inet_addr(address)
        target.sin_port = port.bigEndian
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    init?(ipv6LoopbackPort port: UInt16) {
        let descriptor = Darwin.socket(AF_INET6, SOCK_STREAM, 0)
        var target = sockaddr_in6()
        target.sin6_family = sa_family_t(AF_INET6)
        target.sin6_addr = in6addr_loopback
        target.sin6_port = port.bigEndian
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    func write(_ text: String) {
        _ = Array(text.utf8).withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, 0) }
    }

    // True when the peer closed or reset the connection within `timeout` seconds, rather than leaving it open.
    func isClosedByPeer(within timeout: Int) -> Bool {
        var limit = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        let received = recv(descriptor, &byte, 1, 0)
        return received == 0 || (received < 0 && errno != EAGAIN)
    }

    deinit { close(descriptor) }

    // The first IPv4 address of an interface that is up and isn't loopback, such as the Wi-Fi address.
    static func externalIPv4Address() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var cursor = list
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }
}

// A shareable Mutex, since escaping closures can't capture a noncopyable Mutex directly.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value { mutex.withLock { $0 } }

    func set(_ value: Value) {
        mutex.withLock { $0 = value }
    }

    func increment() -> Value where Value == Int {
        mutex.withLock {
            $0 += 1
            return $0
        }
    }
}
