import OrbitCore
import OrbitEngine
import SwiftUI

// The collapsed pill. Artwork sits concentric with the capsule; hovering swaps the playing indicator for compact
// transport controls. Clicks on the pill expand it, presses that travel past the drag threshold move the panel,
// and neither ever fires a control by accident.
struct PillView: View {
    let size: CGSize
    var forcesHover = false
    let onExpand: () -> Void

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    private var isCompact: Bool { size.height < OrbitTokens.Size.pill(.regular).height }
    private var artworkSize: CGFloat { isCompact ? OrbitTokens.Size.pillArtworkCompact : OrbitTokens.Size.pillArtworkRegular }
    private var inset: CGFloat { (size.height - artworkSize) / 2 }
    private var controlDiameter: CGFloat { isCompact ? OrbitTokens.Size.pillControlCompact : OrbitTokens.Size.pillControlRegular }

    var body: some View {
        let snapshot = playback.snapshot
        let status = PlaybackStatus(account: account, snapshot: snapshot)
        let showsControls = (isHovered || forcesHover) && status.hasTrack
        HStack(spacing: isCompact ? OrbitTokens.Spacing.m : OrbitTokens.Spacing.l - 2) {
            leadingTile(snapshot, status: status)
            titles(snapshot, status: status)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing(snapshot, status: status, showsControls: showsControls)
        }
        .padding(.leading, inset)
        .padding(.trailing, trailingInset(status: status, showsControls: showsControls))
        .frame(width: size.width, height: size.height)
        .contentShape(.capsule)
        .onTapGesture(perform: onExpand)
        .panelDraggable()
        .onHover { hovering in isHovered = hovering }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: showsControls)
        .animation(theme.animation(OrbitTokens.Motion.content), value: snapshot.track?.id)
        .animation(theme.animation(OrbitTokens.Motion.content), value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(snapshot, status: status))
        .accessibilityHint("Opens the player")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onExpand)
        .modifier(PillAccessibilityActions(status: status, snapshot: snapshot))
        .accessibilityIdentifier("orbit.pill")
    }

    // The capsule button and the hover controls are centred in the pill's end cap, so both ends of the pill stay
    // concentric with its curve.
    private func trailingInset(status: PlaybackStatus, showsControls: Bool) -> CGFloat {
        if status == .automationNeeded { return (size.height - OrbitTokens.Size.capsuleButton) / 2 }
        if showsControls { return (size.height - controlDiameter) / 2 }
        return inset + OrbitTokens.Spacing.xs
    }

    @ViewBuilder
    private func leadingTile(_ snapshot: PlaybackSnapshot, status: PlaybackStatus) -> some View {
        if theme.showsArtwork, let track = snapshot.track {
            ArtworkView(url: track.artworkURL, size: artworkSize, cornerRadius: artworkSize / 2, keepsPrevious: true)
                .pausedArtwork(!snapshot.isPlaying)
                .animation(theme.animation(OrbitTokens.Motion.content), value: snapshot.isPlaying)
        } else {
            Circle()
                .fill(OrbitPalette.quietFill(contrast: theme.contrast))
                .frame(width: artworkSize, height: artworkSize)
                .overlay {
                    Image(systemName: tileSymbol(status))
                        .font(.system(size: artworkSize * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
        }
    }

    private func titles(_ snapshot: PlaybackSnapshot, status: PlaybackStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title(snapshot, status: status))
                .font(isCompact ? OrbitTokens.Typography.pillTitleCompact : OrbitTokens.Typography.pillTitleRegular)
                .fadingTruncation()
            if !isCompact, let subtitle = subtitle(snapshot, status: status) {
                Text(subtitle)
                    .font(OrbitTokens.Typography.pillSubtitle)
                    .foregroundStyle(.secondary)
                    .fadingTruncation()
            }
        }
        .id(snapshot.track?.id ?? "\(status)")
        .transition(theme.reducesMotion ? .opacity : .push(from: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private func trailing(_ snapshot: PlaybackSnapshot, status: PlaybackStatus, showsControls: Bool) -> some View {
        if status == .automationNeeded {
            Button("Allow") {
                Task { await account.requestAutomationPermission() }
            }
            .capsuleButton()
            .help("Let Orbit see and control what Spotify is playing on this Mac")
            .transition(.opacity)
        } else if showsControls {
            HStack(spacing: 0) {
                if !isCompact {
                    pillButton("backward.fill", label: "Previous", enabled: snapshot.allows(.skipPrevious)) {
                        await playback.previous()
                    }
                }
                PlayPauseButton(diameter: controlDiameter, glyph: OrbitTokens.Icon.regular)
                pillButton("forward.fill", label: "Next", enabled: snapshot.allows(.skipNext)) {
                    await playback.next()
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
        } else if status.hasTrack {
            PlayingIndicator(isPlaying: snapshot.isPlaying)
                .frame(width: OrbitTokens.Size.playingIndicator)
                .transition(.opacity)
        }
    }

    private func pillButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
        }
        .iconButton(diameter: controlDiameter, glyph: OrbitTokens.Icon.small)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func tileSymbol(_ status: PlaybackStatus) -> String {
        switch status {
        case .automationNeeded, .automationDenied: "hand.raised.fill"
        case .spotifyClosed: "moon.zzz.fill"
        default: "music.note"
        }
    }

    private func title(_ snapshot: PlaybackSnapshot, status: PlaybackStatus) -> String {
        if let track = snapshot.track { return track.name }
        return switch status {
        case .spotifyNotInstalled: "Spotify isn't installed"
        case .spotifyClosed: "Spotify is closed"
        case .automationNeeded, .automationDenied: "Spotify is open"
        default: "Not playing"
        }
    }

    private func subtitle(_ snapshot: PlaybackSnapshot, status: PlaybackStatus) -> String? {
        if let track = snapshot.track { return track.artistLine }
        return switch status {
        case .spotifyNotInstalled: "Orbit works with the desktop app"
        case .spotifyClosed: "Click to start listening"
        case .automationNeeded: "Orbit needs permission"
        case .automationDenied: "Orbit isn't allowed to control it"
        case .idle(let canBrowse): canBrowse ? "Click to pick a playlist" : "Click to open Orbit"
        case .playing, .paused: nil
        }
    }

    private func accessibilitySummary(_ snapshot: PlaybackSnapshot, status: PlaybackStatus) -> String {
        guard let track = snapshot.track else {
            return ["Orbit", title(snapshot, status: status), subtitle(snapshot, status: status)].compactMap { $0 }.joined(separator: ", ")
        }
        return "Orbit, \(track.name) by \(track.artistLine), \(snapshot.isPlaying ? "playing" : "paused")"
    }
}

// The hover controls are invisible to VoiceOver until the pointer arrives, so the pill offers the same commands
// as actions, plus the permission request when that is the next step.
private struct PillAccessibilityActions: ViewModifier {
    let status: PlaybackStatus
    let snapshot: PlaybackSnapshot

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account

    func body(content: Content) -> some View {
        content
            .accessibilityActions {
                if status == .automationNeeded {
                    Button("Allow Orbit to Control Spotify") { Task { await account.requestAutomationPermission() } }
                }
                if status.hasTrack, snapshot.allows(snapshot.isPlaying ? .pause : .resume) {
                    Button(snapshot.isPlaying ? "Pause" : "Play") { Task { await playback.togglePlayPause() } }
                }
                if status.hasTrack, snapshot.allows(.skipNext) {
                    Button("Next Track") { Task { await playback.next() } }
                }
                if status.hasTrack, snapshot.allows(.skipPrevious) {
                    Button("Previous Track") { Task { await playback.previous() } }
                }
            }
    }
}
