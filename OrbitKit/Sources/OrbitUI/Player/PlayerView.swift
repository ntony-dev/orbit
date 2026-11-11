import OrbitCore
import OrbitEngine
import SwiftUI

struct PlayerView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        let snapshot = playback.snapshot
        VStack(spacing: 0) {
            PanelTopBar {
                contextLabel(snapshot)
            }
            if let unavailable = PlayerAvailability(account: account, snapshot: snapshot).blockingState {
                Spacer(minLength: 0)
                blockingMessage(unavailable)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 0) {
                    NowPlayingHeader()
                        .padding(.top, OrbitTokens.Spacing.m)
                    SeekBar()
                        .padding(.top, OrbitTokens.Spacing.l)
                    TransportRow()
                        .padding(.top, OrbitTokens.Spacing.xs)
                    VolumeRow()
                        .padding(.top, OrbitTokens.Spacing.m)
                }
                .padding(.horizontal, OrbitTokens.Spacing.xl)
                PlayerNotice()
                    .padding(.horizontal, OrbitTokens.Spacing.l)
                    .padding(.top, OrbitTokens.Spacing.m)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func contextLabel(_ snapshot: PlaybackSnapshot) -> some View {
        if let context = snapshot.context, snapshot.track != nil {
            Button {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.show(.picker) }
            } label: {
                HStack(spacing: OrbitTokens.Spacing.s) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(context.name ?? "Playing from Spotify")
                        .font(OrbitTokens.Typography.captionEmphasized)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Switch playlists")
            .accessibilityLabel("Playing from \(context.name ?? "Spotify"). Switch playlists")
        } else {
            Text("Orbit")
                .font(OrbitTokens.Typography.captionEmphasized)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func blockingMessage(_ state: PlayerAvailability.Blocking) -> some View {
        switch state {
        case .spotifyNotInstalled:
            StatusMessage(
                symbol: "arrow.down.app",
                title: "Spotify isn't installed",
                message: "Orbit controls the Spotify desktop app. Install it, then reopen Orbit."
            )
        case .spotifyClosed:
            StatusMessage(
                symbol: "moon.zzz",
                title: "Spotify is closed",
                message: "Open it in the background to start listening.",
                actions: [StateAction(title: "Open Spotify", symbol: "play.fill") { SpotifyApp.launchInBackground() }]
            )
        case .automationDenied:
            StatusMessage(
                symbol: "lock.shield",
                title: "Orbit can't control Spotify",
                message: "Allow Orbit in System Settings › Privacy & Security › Automation, then come back.",
                actions: [StateAction(title: "Open Settings") { SpotifyApp.openAutomationSettings() }]
            )
        case .idle(let canBrowse):
            StatusMessage(
                symbol: "music.note",
                title: "Nothing playing",
                message: canBrowse ? "Pick a playlist to start listening." : "Start something in Spotify, or connect your account to pick a playlist here.",
                actions: canBrowse
                    ? [StateAction(title: "Choose a Playlist", symbol: "music.note.list") {
                        withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.show(.picker) }
                    }]
                    : [StateAction(title: "Connect Spotify") { Task { await account.signIn() } }]
            )
        }
    }
}

// What the player can honestly show. Anything that makes transport controls meaningless replaces them; softer
// problems become a notice beneath working controls.
@MainActor
struct PlayerAvailability {
    enum Blocking: Equatable {
        case spotifyNotInstalled
        case spotifyClosed
        case automationDenied
        case idle(canBrowse: Bool)
    }

    let account: AccountStore
    let snapshot: PlaybackSnapshot

    var blockingState: Blocking? {
        guard snapshot.track == nil else { return nil }
        if !account.isSpotifyInstalled { return .spotifyNotInstalled }
        if !account.isSpotifyRunning { return .spotifyClosed }
        if account.automationPermission == .denied { return .automationDenied }
        return .idle(canBrowse: account.authState.isSignedIn)
    }
}

private struct NowPlayingHeader: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        let track = playback.snapshot.track
        HStack(alignment: .center, spacing: OrbitTokens.Spacing.l + OrbitTokens.Spacing.xxs) {
            if theme.showsArtwork {
                ArtworkView(
                    url: track?.artworkURL,
                    size: OrbitTokens.Size.nowPlayingArtwork,
                    cornerRadius: OrbitTokens.Radius.artworkLarge,
                    keepsPrevious: true
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            }
            VStack(alignment: .leading, spacing: OrbitTokens.Spacing.xxs) {
                Text(track?.name ?? "")
                    .font(OrbitTokens.Typography.title)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: OrbitTokens.Spacing.xs) {
                    if track?.isExplicit == true {
                        Image(systemName: "e.square.fill")
                            .font(.system(size: OrbitTokens.Icon.small))
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Explicit")
                    }
                    Text(track?.artistLine ?? "")
                        .font(OrbitTokens.Typography.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(track?.album ?? "")
                    .font(OrbitTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(track?.id)
            .transition(.opacity)
            LikeButton()
        }
        .frame(minHeight: theme.showsArtwork ? OrbitTokens.Size.nowPlayingArtwork : 0)
        .animation(theme.animation(OrbitTokens.Motion.content), value: track?.id)
        .accessibilityElement(children: .contain)
    }
}

private struct LikeButton: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account

    var body: some View {
        let saved = playback.isCurrentTrackSaved
        let isPending = playback.pendingIntents.contains(.toggleSaved)
        Button {
            Task { await playback.toggleSaved() }
        } label: {
            Image(systemName: saved == true ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
        }
        .iconButton(diameter: OrbitTokens.Size.iconButton + 2, glyph: OrbitTokens.Icon.transport - 1, isOn: saved == true, showsOnIndicator: false)
        .disabled(saved == nil || isPending || !account.authState.isSignedIn)
        .help(saved == true ? "Remove from Liked Songs" : "Save to Liked Songs")
        .accessibilityLabel(saved == true ? "Remove from Liked Songs" : "Save to Liked Songs")
    }
}

private struct SeekBar: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var scrubFraction: Double?

    var body: some View {
        let snapshot = playback.snapshot
        let duration = max(0, snapshot.track?.duration ?? 0)
        let canSeek = duration > 0 && snapshot.allows(.seek)
        TimelineView(.animation(minimumInterval: OrbitTokens.Motion.progressInterval, paused: !snapshot.isPlaying || scrubFraction != nil)) { context in
            let position = scrubFraction.map { $0 * duration } ?? snapshot.position(at: context.date)
            let fraction = duration > 0 ? position / duration : 0
            VStack(spacing: OrbitTokens.Spacing.xxs) {
                OrbitSlider(
                    value: fraction,
                    onScrub: { scrubFraction = $0 },
                    onCommit: { committed in
                        scrubFraction = nil
                        Task { await playback.seek(to: committed * duration) }
                    },
                    accessibilityLabel: "Playback position",
                    accessibilityValue: "\(Formatting.time(position)) of \(Formatting.time(duration))",
                    step: duration > 0 ? 10 / duration : 0.05
                )
                .disabled(!canSeek)
                HStack {
                    Text(Formatting.time(position))
                    Spacer()
                    Text("-" + Formatting.time(max(0, duration - position)))
                }
                .font(OrbitTokens.Typography.timecode)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct TransportRow: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        let snapshot = playback.snapshot
        let canRepeat = snapshot.allows(.toggleRepeatContext) || snapshot.allows(.toggleRepeatTrack)
        HStack(spacing: 0) {
            TransportButton(symbol: "shuffle", label: "Shuffle", isOn: snapshot.shuffle, isEnabled: snapshot.allows(.toggleShuffle)) {
                await playback.toggleShuffle()
            }
            Spacer(minLength: 0)
            TransportButton(symbol: "backward.fill", label: "Previous", isEnabled: snapshot.allows(.skipPrevious)) {
                await playback.previous()
            }
            Spacer(minLength: 0)
            PlayPauseButton(diameter: OrbitTokens.Size.primaryTransportButton, glyph: OrbitTokens.Icon.primaryTransport - 4, isProminent: true)
            Spacer(minLength: 0)
            TransportButton(symbol: "forward.fill", label: "Next", isEnabled: snapshot.allows(.skipNext)) {
                await playback.next()
            }
            Spacer(minLength: 0)
            TransportButton(
                symbol: snapshot.repeatMode == .track ? "repeat.1" : "repeat",
                label: repeatLabel(snapshot.repeatMode),
                isOn: snapshot.repeatMode != .off,
                isEnabled: canRepeat
            ) {
                await playback.cycleRepeat()
            }
        }
        .padding(.horizontal, OrbitTokens.Spacing.xs)
    }

    private func repeatLabel(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Repeat"
        case .context: "Repeat All"
        case .track: "Repeat One"
        }
    }
}

private struct VolumeRow: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme
    @State private var draft: Double?
    @State private var lastSent = ContinuousClock.now

    var body: some View {
        let snapshot = playback.snapshot
        let volume = snapshot.volume.map { Double($0) / 100 }
        let canSetVolume = snapshot.allows(.setVolume) && volume != nil
        let shown = draft ?? volume ?? 0
        HStack(spacing: OrbitTokens.Spacing.m) {
            Image(systemName: speakerSymbol(shown, enabled: canSetVolume))
                .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .contentTransition(.symbolEffect(.replace))
            OrbitSlider(
                value: shown,
                onScrub: scrub,
                onCommit: commit,
                accessibilityLabel: "Volume",
                accessibilityValue: canSetVolume ? "\(Int(shown * 100)) percent" : "Unavailable on this device"
            )
            .disabled(!canSetVolume)
            .help(canSetVolume ? "Volume" : "This device doesn't support volume control")
            DeviceChip(device: snapshot.device) {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.push(.devices) }
            }
        }
    }

    private func speakerSymbol(_ level: Double, enabled: Bool) -> String {
        guard enabled else { return "speaker.slash.fill" }
        return switch level {
        case ..<0.01: "speaker.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    // Sends while dragging at a bounded rate so the volume follows the hand without flooding Spotify.
    private func scrub(_ fraction: Double) {
        draft = fraction
        let now = ContinuousClock.now
        guard now - lastSent >= OrbitTokens.Motion.volumeThrottle else { return }
        lastSent = now
        Task { await playback.setVolume(Int((fraction * 100).rounded())) }
    }

    private func commit(_ fraction: Double) {
        draft = fraction
        Task {
            await playback.setVolume(Int((fraction * 100).rounded()))
            draft = nil
        }
    }
}

private struct DeviceChip: View {
    let device: PlaybackDevice?
    let action: () -> Void

    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: OrbitTokens.Spacing.xs + 1) {
                Image(systemName: device?.kind.symbol ?? "hifispeaker")
                    .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                Text(device?.name ?? "Devices")
                    .font(OrbitTokens.Typography.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 92, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, OrbitTokens.Spacing.m)
            .frame(height: 24)
            .background {
                Capsule().fill(isHovered ? OrbitPalette.hoverFill(contrast: theme.contrast) : OrbitPalette.quietFill(contrast: theme.contrast))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
        .help("Choose where Spotify plays")
        .accessibilityLabel("Playing on \(device?.name ?? "unknown device"). Choose device")
    }
}

// One notice at a time beneath the controls, most actionable first.
enum PlayerNoticeKind: Hashable {
    case automationDenied
    case automationUndetermined
    case commandFailed(OrbitError)
    case deviceRestricted(String)

    // Extra surface height the player needs while a notice is showing.
    static let height: CGFloat = 58

    @MainActor
    static func current(account: AccountStore, playback: PlaybackCoordinator) -> PlayerNoticeKind? {
        guard playback.snapshot.track != nil else { return nil }
        if account.automationPermission == .denied { return .automationDenied }
        if account.automationPermission == .notDetermined, account.isSpotifyRunning { return .automationUndetermined }
        if let error = playback.lastError { return .commandFailed(error) }
        if let device = playback.snapshot.device, device.isRestricted { return .deviceRestricted(device.name) }
        return nil
    }
}

private struct PlayerNotice: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(\.orbitTheme) private var theme

    var body: some View {
        let kind = PlayerNoticeKind.current(account: account, playback: playback)
        Group {
            if let kind {
                callout(kind)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .animation(theme.animation(OrbitTokens.Motion.content), value: kind)
    }

    private func callout(_ kind: PlayerNoticeKind) -> Callout {
        switch kind {
        case .automationDenied:
            Callout(
                symbol: "lock.shield",
                message: "Orbit can't control Spotify on this Mac",
                detail: "Allow it in Privacy & Security › Automation.",
                action: StateAction(title: "Open Settings") { SpotifyApp.openAutomationSettings() }
            )
        case .automationUndetermined:
            Callout(
                symbol: "hand.raised",
                message: "Allow Orbit to control Spotify",
                detail: "Makes play, skip and volume instant on this Mac.",
                action: StateAction(title: "Allow…") { Task { await account.requestAutomationPermission() } }
            )
        case .commandFailed(let error):
            Callout(
                symbol: "exclamationmark.triangle",
                message: error.message,
                detail: error.recoveryHint,
                onDismiss: { playback.dismissError() }
            )
        case .deviceRestricted(let name):
            Callout(
                symbol: "hifispeaker.badge.exclamationmark",
                message: "\(name) can't be controlled from Orbit",
                detail: "Choose another device to use these controls."
            )
        }
    }
}
