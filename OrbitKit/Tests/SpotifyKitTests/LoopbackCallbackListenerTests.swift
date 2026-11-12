import Foundation
import OrbitCore
@testable import SpotifyKit
import Synchronization
import Testing

// Every test binds a free port from LocalPorts, never 8888, so a real sign-in on this Mac is unaffected.
@Suite(.serialized)
struct LoopbackCallbackListenerTests {
    private func listener(port: UInt16, timeout: Duration = .seconds(10)) -> LoopbackCallbackListener {
        LoopbackCallbackListener(port: port, path: "/callback", timeout: timeout)
    }

    private func codeHandler(_ components: URLComponents) -> Result<String, OrbitError>? {
        AuthorizationCallback.result(from: components, expectedState: "s1")
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

    // Any web page or local process can reach the port, so a request without this sign-in's state must neither
    // complete nor end the sign-in.
    @Test func callbacksWithoutTheExpectedStateAreRefusedAndTheWaitContinues() async throws {
        let port = LocalPorts.free()
        let refused = Locked<[Served]>([])
        let code = try await listener(port: port).receive(
            whenReady: {
                for query in ["code=evil&state=forged", "code=evil", "error=access_denied", "error=access_denied&state=forged", "<script>"] {
                    let page = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?\(query)")!)
                    refused.set(refused.value + [page])
                }
                _ = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=real&state=s1")!)
            },
            handle: codeHandler
        )
        #expect(code == "real")
        #expect(refused.value.map { $0?.status } == [400, 400, 400, 400, 400])
        #expect(refused.value.allSatisfy { $0?.body.contains("Sign-in didn't finish.") == true })
        #expect(!refused.value.contains { $0?.body.contains("evil") == true || $0?.body.contains("script>") == true })
    }

    @Test func aGenuineFailureEndsTheWaitAndShowsTheFailurePage() async throws {
        let port = LocalPorts.free()
        let page = Self.pageStream()
        await #expect(throws: OrbitError.unexpected(detail: "Spotify sign-in failed (server_error).")) {
            try await listener(port: port).receive(
                whenReady: {
                    page.continuation.yield(try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?error=server_error&state=s1")!))
                },
                handle: codeHandler
            )
        }
        var iterator = page.stream.makeAsyncIterator()
        let served = await iterator.next() ?? nil
        #expect(served?.body.contains("Sign-in didn't finish.") == true)
    }

    @Test func acceptsNothingExceptIPv4Loopback() async throws {
        let port = LocalPorts.free()
        let external = RawConnection.externalIPv4Address()
        let reached = Locked<[String]>([])
        let code = try await listener(port: port).receive(
            whenReady: {
                if let external, RawConnection(ipv4: external, port: port) != nil { reached.set(reached.value + [external]) }
                if RawConnection(ipv6LoopbackPort: port) != nil { reached.set(reached.value + ["::1"]) }
                _ = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=abc&state=s1")!)
            },
            handle: codeHandler
        )
        #expect(code == "abc")
        #expect(reached.value.isEmpty)
    }

    // Browsers open spare connections they may never use; none may outlive the sign-in.
    @Test func idleConnectionsAreClosedWhenTheCallbackArrives() async throws {
        let port = LocalPorts.free()
        let idle = Locked<[RawConnection]>([])
        _ = try await listener(port: port).receive(
            whenReady: {
                if let connection = RawConnection(ipv4: "127.0.0.1", port: port) { idle.set([connection]) }
                _ = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=abc&state=s1")!)
            },
            handle: codeHandler
        )
        let connection = try #require(idle.value.first)
        #expect(connection.isClosedByPeer(within: 3))
    }

    @Test func idleConnectionsAreClosedWhenSignInIsCancelled() async throws {
        let port = LocalPorts.free()
        let idle = Locked<[RawConnection]>([])
        let ready = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            try await listener(port: port).receive(whenReady: {
                // A request head that never ends, so the listener has accepted the connection and is reading it.
                if let connection = RawConnection(ipv4: "127.0.0.1", port: port) {
                    connection.write("GET /callback?code=abc")
                    idle.set([connection])
                }
                try? await Task.sleep(for: .milliseconds(200))
                ready.continuation.yield()
            }, handle: codeHandler)
        }
        for await _ in ready.stream { break }
        task.cancel()
        _ = try? await task.value
        let connection = try #require(idle.value.first)
        #expect(connection.isClosedByPeer(within: 3))
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

    // Each round binds the port the previous round just gave up; a listener that returned before its socket closed
    // would fail here with port-in-use.
    @Test func cancelledListenerReleasesThePortBeforeReturning() async throws {
        let port = LocalPorts.free()
        for round in 0..<20 {
            let ready = AsyncStream.makeStream(of: Void.self)
            let task = Task {
                // Ends the wait below if the listener fails to bind, so a regression fails instead of hanging.
                defer { ready.continuation.finish() }
                return try await listener(port: port).receive(whenReady: { ready.continuation.yield() }, handle: codeHandler)
            }
            for await _ in ready.stream { break }
            task.cancel()
            do {
                _ = try await task.value
                Issue.record("Round \(round) returned instead of being cancelled")
            } catch {
                #expect(error as? OrbitError == .cancelled, "Round \(round)")
            }
        }
    }

    // A served callback leaves the accepted connection in TIME_WAIT; an immediate retry must still bind.
    @Test func servedCallbackLeavesThePortImmediatelyReusable() async throws {
        let port = LocalPorts.free()
        for attempt in 0..<10 {
            let code = try await listener(port: port).receive(
                whenReady: { _ = try? await LocalHTTP.get(URL(string: "http://127.0.0.1:\(port)/callback?code=c\(attempt)&state=s1")!) },
                handle: codeHandler
            )
            #expect(code == "c\(attempt)")
        }
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
