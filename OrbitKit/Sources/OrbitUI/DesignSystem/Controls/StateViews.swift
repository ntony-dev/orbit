import OrbitCore
import SwiftUI

struct StateAction {
    let title: String
    var symbol: String?
    var isProminent = true
    let perform: () -> Void
}

// Empty, error and permission states share one quiet layout: a glyph, a short title, one line of guidance and at
// most two actions.
struct StatusMessage: View {
    let symbol: String
    let title: String
    var message: String?
    var tone: Tone = .neutral
    var actions: [StateAction] = []

    enum Tone {
        case neutral, warning
    }

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        VStack(spacing: OrbitTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone == .warning ? AnyShapeStyle(OrbitPalette.warning) : AnyShapeStyle(.secondary))
                .frame(height: 28)
            VStack(spacing: OrbitTokens.Spacing.xs) {
                Text(title)
                    .font(OrbitTokens.Typography.headline)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(OrbitTokens.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !actions.isEmpty {
                HStack(spacing: OrbitTokens.Spacing.m) {
                    ForEach(actions.indices, id: \.self) { index in
                        let action = actions[index]
                        Button(action: action.perform) {
                            if let symbol = action.symbol {
                                Label(action.title, systemImage: symbol)
                            } else {
                                Text(action.title)
                            }
                        }
                        .capsuleButton(prominent: action.isProminent)
                    }
                }
                .padding(.top, OrbitTokens.Spacing.xs)
            }
        }
        .padding(.horizontal, OrbitTokens.Spacing.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension StatusMessage {
    // Every OrbitError maps to a short title and its recovery hint; retryable errors get a Try Again action.
    init(error: OrbitError, retry: (() -> Void)? = nil) {
        let isRateLimit = switch error {
        case .rateLimited, .quotaExceeded: true
        default: false
        }
        let symbol = switch error {
        case .network: "wifi.exclamationmark"
        case .rateLimited, .quotaExceeded: "hourglass"
        case .notSignedIn, .authExpired, .notAllowlisted: "person.crop.circle.badge.exclamationmark"
        case .playlistItemsUnavailable, .contentRestricted: "lock"
        case .noActiveDevice, .deviceRestricted: "hifispeaker.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
        let actions = retry.map { [StateAction(title: "Try Again", symbol: "arrow.clockwise", isProminent: !isRateLimit, perform: $0)] } ?? []
        self.init(
            symbol: symbol,
            title: error.message,
            message: error.recoveryHint,
            tone: isRateLimit ? .neutral : .warning,
            actions: actions
        )
    }
}

// An inline, dismissible strip for problems that should not replace the screen, such as a failed command.
struct Callout: View {
    let symbol: String
    let message: String
    var detail: String?
    var action: StateAction?
    var onDismiss: (() -> Void)?

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: OrbitTokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: OrbitTokens.Icon.regular, weight: .semibold))
                .foregroundStyle(OrbitPalette.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(message)
                    .font(OrbitTokens.Typography.captionEmphasized)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(OrbitTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action.title, action: action.perform)
                    .capsuleButton()
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .iconButton(diameter: 20, glyph: 9)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, OrbitTokens.Spacing.l)
        .padding(.vertical, OrbitTokens.Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: OrbitTokens.Radius.callout, style: .continuous)
                .fill(OrbitPalette.quietFill(contrast: theme.contrast))
        }
        .accessibilityElement(children: .contain)
    }
}

// Placeholder rows shaped like the content that is coming, so loading never shows an empty surface or a lone
// spinner. They breathe gently unless motion is reduced.
struct SkeletonRows: View {
    var count = 5
    var artwork = true

    @Environment(\.orbitTheme) private var theme
    @State private var isDimmed = false

    var body: some View {
        VStack(spacing: OrbitTokens.Spacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: OrbitTokens.Spacing.l) {
                    if artwork {
                        RoundedRectangle(cornerRadius: OrbitTokens.Radius.artwork, style: .continuous)
                            .frame(width: OrbitTokens.Size.rowArtwork, height: OrbitTokens.Size.rowArtwork)
                    }
                    VStack(alignment: .leading, spacing: OrbitTokens.Spacing.s) {
                        Capsule().frame(width: [132, 104, 150, 92, 120][index % 5], height: 8)
                        Capsule().frame(width: [70, 88, 60, 80, 54][index % 5], height: 6).opacity(0.6)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .frame(height: OrbitTokens.Size.rowHeight)
            }
        }
        .foregroundStyle(OrbitPalette.quietFill(contrast: theme.contrast))
        .opacity(isDimmed ? 0.55 : 1)
        .onAppear {
            guard !theme.reducesMotion else { return }
            withAnimation(theme.animation(OrbitTokens.Motion.loadingPulse).repeatForever(autoreverses: true)) { isDimmed = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

// A section title, or with `isSubheading` a quieter label for a group inside a section (Spotify's songs, albums
// and playlists under Search Spotify).
struct SectionHeader: View {
    let title: String
    var trailing: String?
    var isSubheading = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(isSubheading ? OrbitTokens.Typography.caption : OrbitTokens.Typography.sectionHeading)
                .foregroundStyle(isSubheading ? .tertiary : .secondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(OrbitTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, OrbitTokens.Spacing.m)
        .padding(.top, isSubheading ? OrbitTokens.Spacing.xs : OrbitTokens.Spacing.m)
        .padding(.bottom, OrbitTokens.Spacing.xxs)
        .accessibilityAddTraits(.isHeader)
    }
}
