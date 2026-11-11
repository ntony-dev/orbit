import OrbitCore
import OrbitEngine
import SwiftUI

// Stands in for screens that need the Web API until the account is connected. It never flashes a sign-in prompt
// while the stored session is still being checked.
struct AccountGate<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(AccountStore.self) private var account

    var body: some View {
        switch account.authState {
        case .signedIn:
            content
        case .unknown:
            SkeletonRows(count: 6)
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.top, OrbitTokens.Spacing.l)
                .frame(maxHeight: .infinity, alignment: .top)
        case .signedOut:
            centered { signedOut }
        case .authorizing:
            centered {
                VStack(spacing: OrbitTokens.Spacing.l) {
                    ProgressView().controlSize(.small)
                    StatusMessage(
                        symbol: "safari",
                        title: "Finish signing in in your browser",
                        message: "Orbit is waiting for Spotify to send you back here."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var signedOut: some View {
        if let error = account.lastError, error != .cancelled {
            StatusMessage(error: error) {
                account.dismissError()
                Task { await account.signIn() }
            }
        } else {
            StatusMessage(
                symbol: "person.crop.circle.badge.plus",
                title: "Connect your Spotify account",
                message: "Browse your playlists, search and switch devices from Orbit. Playback controls work without it.",
                actions: [StateAction(title: "Connect Spotify") { Task { await account.signIn() } }]
            )
        }
    }

    private func centered<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        inner().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
