import OrbitCore
import SpotifyKit
import Testing

struct SeamTests {
    @Test func signInWithoutClientIDFailsWithMissingClientID() async {
        let authorizer = SpotifyAuthorizer { nil }
        await #expect(throws: OrbitError.missingClientID) { try await authorizer.signIn() }
    }

    @Test func unimplementedSeamsFailLoudly() async {
        let authorizer = SpotifyAuthorizer { "client-id" }
        await #expect(throws: OrbitError.notImplemented(feature: "Spotify sign-in")) { try await authorizer.signIn() }
        let client = SpotifyWebClient(authorizer: authorizer)
        await #expect(throws: OrbitError.notImplemented(feature: "The Spotify Web API")) { try await client.currentUser() }
    }

    @Test func restoringWithoutStoredSessionSignsOut() async throws {
        let authorizer = SpotifyAuthorizer { nil }
        #expect(await authorizer.currentState() == .unknown)
        try await authorizer.restoreSession()
        #expect(await authorizer.currentState() == .signedOut)
    }
}
