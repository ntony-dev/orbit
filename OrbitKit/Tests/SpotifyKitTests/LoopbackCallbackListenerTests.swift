import Foundation
import OrbitCore
@testable import SpotifyKit
import Synchronization
import Testing

// Every test binds a kernel-assigned free port, never 8888, so a real sign-in on this Mac is unaffected.
@Suite(.serialized)
struct LoopbackCallbackListenerTests {
    private func listener(port: UInt16, timeout: Duration = .seconds(10)) -> LoopbackCallbackListener {
        LoopbackCallbackListener(port: port, path: "/callback", timeout: timeout)
    }

    private func codeHandler(_ components: URLComponents) -> Result<String, OrbitError> {
        Result { () throws(OrbitError) in try AuthorizationCallback.code(from: components, expectedState: "s1") }
    }

    // The listener can return before the client has read the whole page, so the page arrives through a stream.
    private typealias Served = (status: Int, body: String)?

    private static func pageStream() -> (stream: AsyncStream<Served>, continuation: AsyncStream<Served>.Continuation) {
        AsyncStream.makeStream(of: Served.self)
    }

    @Test func servesClosePageAndReturnsTheCode() async throws {
        let port = LocalPorts.free()
        let page = Self.pageStream()
        let code = try await listener(port: port).receive(
            whenReady: {
                page.continuation.yield(try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=abc&state=s1")!))
            },
            handle: codeHandler
        )
        #expect(code == "abc")
        var iterator = page.stream.makeAsyncIterator()
        let served = try #require(await iterator.next() ?? nil)
        #expect(served.status == 200)
        #expect(served.body.contains("You can close this tab."))
        #expect(served.body.contains("signed in"))
    }

    @Test func ignoresOtherPathsUntilTheCallbackArrives() async throws {
        let port = LocalPorts.free()
        let faviconStatus = Locked<Int?>(nil)
        let code = try await listener(port: port).receive(
            whenReady: {
                let favicon = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
                faviconStatus.set(favicon?.status)
                _ = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=xyz&state=s1")!)
            },
            handle: codeHandler
        )
        #expect(code == "xyz")
        #expect(faviconStatus.value == 404)
    }

    @Test func stateMismatchFailsAndShowsTheFailurePage() async throws {
        let port = LocalPorts.free()
        let page = Self.pageStream()
        await #expect(throws: OrbitError.self) {
            try await listener(port: port).receive(
                whenReady: {
                    page.continuation.yield(try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=abc&state=forged")!))
                },
                handle: codeHandler
            )
        }
        var iterator = page.stream.makeAsyncIterator()
        let served = await iterator.next() ?? nil
        #expect(served?.body.contains("Sign-in didn't finish.") == true)
    }

    @Test func reportsPortInUse() async {
        let occupier = LocalPorts.Occupier()
        await #expect(throws: OrbitError.callbackPortInUse(port: Int(occupier.port))) {
            try await listener(port: occupier.port).receive(whenReady: {}, handle: codeHandler)
        }
        withExtendedLifetime(occupier) {}
    }

    @Test func timesOut() async {
        let port = LocalPorts.free()
        await #expect(throws: OrbitError.unexpected(detail: "Timed out waiting for Spotify sign-in.")) {
            try await listener(port: port, timeout: .milliseconds(200)).receive(whenReady: {}, handle: codeHandler)
        }
    }

    @Test func cancellationStopsTheListenerAndFreesThePort() async throws {
        let port = LocalPorts.free()
        let ready = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            try await listener(port: port).receive(whenReady: { ready.continuation.yield() }, handle: codeHandler)
        }
        for await _ in ready.stream { break }
        task.cancel()
        await #expect(throws: OrbitError.cancelled) { try await task.value }

        // The port must be reusable straight away, or a retried sign-in would hit port-in-use.
        let code = try await listener(port: port).receive(
            whenReady: { _ = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=again&state=s1")!) },
            handle: codeHandler
        )
        #expect(code == "again")
    }

    @Test func failureFromWhenReadyEndsTheWait() async {
        let port = LocalPorts.free()
        await #expect(throws: OrbitError.unexpected(detail: "no browser")) {
            try await listener(port: port).receive(
                whenReady: { () async throws(OrbitError) in throw .unexpected(detail: "no browser") },
                handle: codeHandler
            )
        }
    }
}
