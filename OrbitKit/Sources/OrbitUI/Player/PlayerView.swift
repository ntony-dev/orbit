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
        let status = PlaybackStatus(account: account, snapshot: snapshot)
        VStack(spacing: 0) {
            PanelTopBar {
                ContextLabel(snapshot: snapshot)
            } accessory: {
                SettingsButton()
            }
            if status.hasTrack {
                VStack(spacing: 0) {
                    NowPlayingHeader()
                        .padding(.top, OrbitTokens.Spacing.s)
                    SeekBar()
                        .padding(.top, OrbitTokens.Spacing.m + OrbitTokens.Spacing.xxs)
                    TransportRow()
                        .padding(.top, OrbitTokens.Spacing.xs)
                    VolumeRow()
                        .padding(.top, OrbitTokens.Spacing.m)
                }
                .padding(.horizontal, OrbitTokens.Spacing.xl)
                if navigator.drawer == .devices {
                    DeviceListView()
                        .padding(.horizontal, OrbitTokens.Spacing.m)
                        .transition(drawerTransition)
                }
                if navigator.drawer == .queue {
                    QueueListView()
                        .padding(.horizontal, OrbitTokens.Spacing.m)
                        .transition(drawerTransition)
                }
                PlayerNotice()
                    .padding(.horizontal, OrbitTokens.Spacing.l)
                    .padding(.top, OrbitTokens.Spacing.m)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                blockingMessage(status)
                    .padding(.horizontal, OrbitTokens.Spacing.xl)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .animation(theme.animation(OrbitTokens.Motion.content), value: status)
        .panelKeyFocusTarget()
    }

    // A drawer fades in while the surface grows to make room for it, settling a few points down as if it slid
    // out from under the volume row.
    private var drawerTransition: AnyTransition {
        let fadeOut = AnyTransition.opacity.animation(theme.animation(OrbitTokens.Motion.screenFadeOut))
        guard !theme.reducesMotion else { return .asymmetric(insertion: .opacity, removal: fadeOut) }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: -OrbitTokens.Spacing.s)), removal: fadeOut)
    }

    @ViewBuilder
    private func blockingMessage(_ status: PlaybackStatus) -> some View {
        switch status {
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
        case .automationNeeded:
            StatusMessage(
                symbol: "hand.raised",
                title: "Allow Orbit to control Spotify",
                message: "Spotify is open, but Orbit needs your permission to see what's playing and control it. macOS asks once.",
                actions: [StateAction(title: "Allow…") { Task { await account.requestAutomationPermission() } }]
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
                    ? [StateAction(title: "Choose a Playlist", symbol: "square.stack") {
                        withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.show(.library) }
                    }]
                    : [StateAction(title: "Connect Spotify") { Task { await account.signIn() } }]
            )
        case .playing, .paused:
            EmptyView()
        }
    }
}

// The playing context names where the music comes from and doubles as the way into the library, so it brightens
// and shows a chevron on hover like any other link.
private struct ContextLabel: View {
    let snapshot: PlaybackSnapshot

    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        if let context = snapshot.context, snapshot.track != nil {
            Button {
                withAnimation(theme.animation(OrbitTokens.Motion.navigate)) { navigator.show(.library) }
            } label: {
                HStack(spacing: OrbitTokens.Spacing.s) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: OrbitTokens.Icon.small, weight: .semibold))
                        .foregroundStyle(isHovered ? .secondary : .tertiary)
                    Text(context.name ?? "Playing from Spotify")
                        .font(OrbitTokens.Typography.captionEmphasized)
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: OrbitTokens.Icon.small - 2, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered ? 1 : 0)
                        .offset(x: isHovered || theme.reducesMotion ? 0 : -OrbitTokens.Spacing.xs)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isHovered)
            .help("Switch playlists")
            .accessibilityLabel("Playing from \(context.name ?? "Spotify")")
            .accessibilityHint("Opens your library")
        } else {
            Text("Orbit")
                .font(OrbitTokens.Typography.captionEmphasized)
                .foregroundStyle(.secondary)
        }
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
                .pausedArtwork(!playback.snapshot.isPlaying)
                .animation(theme.animation(OrbitTokens.Motion.toggle), value: playback.snapshot.isPlaying)
            }
            // Title up to two lines, artist on one: the pair is centred on the artwork, so a one-line title sits
            // level with the cover's middle and a two-line one fills it, rather than leaving a hole beneath.
            VStack(alignment: .leading, spacing: OrbitTokens.Spacing.xs) {
                Text(title(track))
                    .font(OrbitTokens.Typography.nowPlayingTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: OrbitTokens.Spacing.xs) {
                    if track?.isExplicit == true {
                        Image(systemName: "e.square.fill")
                            .font(.system(size: OrbitTokens.Icon.small))
                            .foregroundStyle(.secondary)
                    }
                    Text(track?.artistLine ?? "")
                        .font(OrbitTokens.Typography.nowPlayingArtist)
                        .foregroundStyle(.secondary)
                        .fadingTruncation()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(track?.id)
            .transition(trackTransition)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(trackDescription(track))
            .accessibilityAddTraits(.isHeader)
            LikeButton()
        }
        .frame(minHeight: theme.showsArtwork ? OrbitTokens.Size.nowPlayingArtwork : 0)
        .animation(theme.animation(OrbitTokens.Motion.content), value: track?.id)
    }

    // The new title rises a few points into place while the old one fades, the same direction the pill uses.
    private var trackTransition: AnyTransition {
        guard !theme.reducesMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: OrbitTokens.Spacing.s)),
            removal: .opacity.animation(theme.animation(OrbitTokens.Motion.screenFadeOut))
        )
    }

    private func title(_ track: Track?) -> String {
        UIDebugOptions.current.trackTitle ?? track?.name ?? ""
    }

    private func trackDescription(_ track: Track?) -> String {
        guard let track else { return "" }
        let explicit = track.isExplicit ? "Explicit" : nil
        return [title(track), track.artistLine, explicit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct LikeButton: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account

    var body: some View {
        let saved = playback.isCurrentTrackSaved
        let isPending = playback.pendingIntents.contains(.toggleSaved)
        let isSignedIn = account.authState.isSignedIn
        let symbol = saved == true ? "heart.fill" : "heart"
        let diameter = OrbitTokens.Size.iconButton + 2
        let glyph = OrbitTokens.Icon.transport - 1
        Button {
            Task { await playback.toggleSaved() }
        } label: {
            Image(systemName: symbol)
                .contentTransition(.identity)
        }
        .iconButton(
            diameter: diameter,
            glyph: glyph,
            isOn: saved == true,
            isToggle: true,
            showsOnIndicator: false
        )
        // The heart's ink, not its circle, ends on the margin, so the circle reaches into the padding.
        .inkAligned(.trailing, GlyphInk.symbol(symbol, size: glyph), in: diameter)
        .disabled(saved == nil || !isSignedIn)
        // The heart has already flipped while the request runs; dimming it as disabled for that moment made the
        // toggle look slow, so it only ignores clicks until Spotify answers.
        .allowsHitTesting(!isPending)
        .help(help(saved: saved, isSignedIn: isSignedIn))
        .accessibilityLabel("Liked Songs")
        .accessibilityValue(saved == true ? "Saved" : "Not saved")
        .accessibilityAddTraits(.isToggle)
    }

    private func help(saved: Bool?, isSignedIn: Bool) -> String {
        if !isSignedIn { return "Connect Spotify to save songs" }
        return saved == true ? "Remove from Liked Songs" : "Save to Liked Songs"
    }
}

private struct SeekBar: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.orbitTheme) private var theme
    @State private var scrubFraction: Double?

    var body: some View {
        let snapshot = playback.snapshot
        let duration = max(0, snapshot.track?.duration ?? 0)
        let canSeek = duration > 0 && snapshot.allows(.seek)
        let isScrubbing = scrubFraction != nil
        TimelineView(.animation(minimumInterval: OrbitTokens.Motion.progressInterval, paused: !snapshot.isPlaying || isScrubbing)) { context in
            let position = scrubFraction.map { $0 * duration } ?? snapshot.position(at: context.date)
            let fraction = duration > 0 ? position / duration : 0
            // The slider spans the content width; elapsed and remaining sit at its ends on a row of their own, so
            // the bar's length never depends on how wide the times are.
            VStack(spacing: 0) {
                OrbitSlider(
                    value: fraction,
                    onScrub: { scrubFraction = $0 },
                    onCommit: { committed in
                        // Cleared in the same main-actor turn that applies the coordinator's optimistic position, so
                        // the knob never snaps back to the old time for a frame.
                        Task {
                            scrubFraction = nil
                            await playback.seek(to: committed * duration)
                        }
                    },
                    accessibilityLabel: "Playback position",
                    accessibilityValue: "\(Self.spoken(position)) of \(Self.spoken(duration))",
                    step: duration > 0 ? PlayerKeyCommand.seekStep / duration : 0.05
                )
                .disabled(!canSeek)
                HStack(spacing: 0) {
                    TimeLabel(text: Formatting.time(position), edge: .leading, isEmphasized: isScrubbing)
                    Spacer(minLength: OrbitTokens.Spacing.m)
                    TimeLabel(text: "-" + Formatting.time(max(0, duration - position)), edge: .trailing, isEmphasized: false)
                }
                .frame(height: OrbitTokens.Size.timecodeRow)
            }
            .animation(theme.animation(OrbitTokens.Motion.hover), value: isScrubbing)
        }
    }

    static func spoken(_ interval: TimeInterval) -> String {
        Duration.seconds(max(0, Int(interval.rounded(.down))))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

// Previous, play and next form one group centred on the panel, spaced by their ink rather than their frames, with
// shuffle and repeat out at the margins, as in Apple Music's mini player. The group is placed around the disc
// rather than between spacers, so it stays centred whatever the outer glyphs measure. The buttons are declared in
// reading order, the order VoiceOver and keyboard focus follow.
private struct TransportRow: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        let snapshot = playback.snapshot
        let canRepeat = snapshot.allows(.toggleRepeatContext) || snapshot.allows(.toggleRepeatTrack)
        let disc = OrbitTokens.Size.primaryTransportButton
        let shuffle = TransportButton(symbol: "shuffle", label: "Shuffle", isToggle: true, isOn: snapshot.shuffle, isEnabled: snapshot.allows(.toggleShuffle)) {
            await playback.toggleShuffle()
        }
        let previous = TransportButton(
            symbol: "backward.fill", label: "Previous", isEnabled: snapshot.allows(.skipPrevious),
            diameter: OrbitTokens.Size.skipTransportButton, glyph: OrbitTokens.Icon.skipTransport
        ) {
            await playback.previous()
        }
        let next = TransportButton(
            symbol: "forward.fill", label: "Next", isEnabled: snapshot.allows(.skipNext),
            diameter: OrbitTokens.Size.skipTransportButton, glyph: OrbitTokens.Icon.skipTransport
        ) {
            await playback.next()
        }
        let repeatButton = TransportButton(
            symbol: snapshot.repeatMode == .track ? "repeat.1" : "repeat",
            label: "Repeat",
            help: repeatHelp(snapshot.repeatMode),
            isToggle: true,
            isOn: snapshot.repeatMode != .off,
            accessibilityValue: repeatValue(snapshot.repeatMode),
            isEnabled: canRepeat
        ) {
            await playback.cycleRepeat()
        }
        ZStack {
            shuffle
                .inkAligned(.leading, shuffle.ink, in: shuffle.diameter)
                .frame(maxWidth: .infinity, alignment: .leading)
            previous
                .offset(x: TransportLayout.previousOffset(disc: disc, ink: previous.ink))
            PlayPauseButton(diameter: disc, glyph: OrbitTokens.Icon.primaryTransport - 4, isProminent: true)
            next
                .offset(x: TransportLayout.nextOffset(disc: disc, ink: next.ink))
            repeatButton
                .inkAligned(.trailing, repeatButton.ink, in: repeatButton.diameter)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: disc)
    }

    private func repeatValue(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Off"
        case .context: "All"
        case .track: "One"
        }
    }

    private func repeatHelp(_ mode: RepeatMode) -> String {
        switch mode {
        case .off: "Repeat"
        case .context: "Repeating all · Click to repeat one"
        case .track: "Repeating one · Click to turn off"
        }
    }
}

// Where previous and next sit around the play disc, as offsets of their centres from the disc's: each glyph's ink
// is `Spacing.transportGroup` from the disc's edge, whatever its side bearings.
enum TransportLayout {
    static func previousOffset(disc: CGFloat, ink: GlyphInk) -> CGFloat {
        -(disc / 2 + OrbitTokens.Spacing.transportGroup + ink.trailing)
    }

    static func nextOffset(disc: CGFloat, ink: GlyphInk) -> CGFloat {
        disc / 2 + OrbitTokens.Spacing.transportGroup + ink.leading
    }
}

// A full-width volume slider with the queue and device buttons at its end, as in Spotify: the slider gets the
// row, and what plays next and where it plays stay one click away without taking room.
private struct VolumeRow: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var draft: Double?
    @State private var lastSent = ContinuousClock.now

    var body: some View {
        let snapshot = playback.snapshot
        let volume = snapshot.volume.map { Double($0) / 100 }
        let canSetVolume = snapshot.allows(.setVolume) && volume != nil
        let shown = draft ?? volume ?? 0
        let speaker = speakerSymbol(shown, enabled: canSetVolume)
        let speakerInk = GlyphInk.symbol(speaker, size: OrbitTokens.Icon.regular)
        HStack(spacing: 0) {
            // Pinned by its ink to the slot's leading edge, so the speaker starts on the margin at every level.
            Image(systemName: speaker)
                .font(.system(size: OrbitTokens.Icon.regular, weight: .semibold))
                .foregroundStyle(.secondary)
                .alignmentGuide(.leading) { $0.width / 2 - speakerInk.leading }
                .frame(width: OrbitTokens.Size.speakerSlot, alignment: .leading)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
                .padding(.trailing, OrbitTokens.Spacing.xs)
            OrbitSlider(
                value: shown,
                onScrub: scrub,
                onCommit: commit,
                accessibilityLabel: "Volume",
                accessibilityValue: canSetVolume ? shown.formatted(.percent.precision(.fractionLength(0))) : "Unavailable on this device",
                step: Double(PlayerKeyCommand.volumeStep) / 100
            )
            .disabled(!canSetVolume)
            .help(canSetVolume ? "Volume" : "This device doesn't support volume control")
            QueueButton()
                .padding(.leading, OrbitTokens.Spacing.volumeToQueue)
                .padding(.trailing, OrbitTokens.Spacing.queueToDevice)
            DeviceButton(device: snapshot.device)
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

// A time at one end of the seek bar, its ink on the margin. The elapsed time's first digit changes at most once a
// minute, so its own bearing is used; the remaining time's last digit changes every second, so its bearing is a
// "0"'s, the shape most digits share, and the label stays still instead of shuffling as the seconds tick (a
// final "1", which sits well inside its advance, ends about 1.5 short of the margin).
private struct TimeLabel: View {
    let text: String
    let edge: HorizontalEdge
    let isEmphasized: Bool

    var body: some View {
        let font = isEmphasized ? OrbitTokens.Typography.timecodeEmphasized : OrbitTokens.Typography.timecode
        let bearing = edge == .leading
            ? TextBearings.of(String(text.prefix(1)), font: font).leading
            : TextBearings.of("0", font: font).trailing
        // While scrubbing, the time being chosen brightens so the eye has one number to follow.
        Text(text)
            .font(font)
            .foregroundStyle(isEmphasized ? .primary : .secondary)
            .fixedSize()
            .padding(edge == .leading ? .leading : .trailing, -bearing)
            .accessibilityHidden(true)
    }
}

// Shows and hides a drawer in place, taking the accent while it is open, so the same click that opened it closes
// it. Opening one drawer closes the other.
private struct DrawerToggle: View {
    let drawer: PlayerDrawer
    let symbol: String
    let label: String
    let help: (Bool) -> String
    var value: String?
    let hint: (Bool) -> String
    let identifier: String

    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme

    static let diameter = OrbitTokens.Size.iconButton
    static let glyph = OrbitTokens.Icon.regular + 1

    var ink: GlyphInk {
        GlyphInk.symbol(symbol, size: Self.glyph)
    }

    var body: some View {
        let isOpen = navigator.drawer == drawer
        Button {
            withAnimation(theme.animation(OrbitTokens.Motion.content)) { navigator.toggle(drawer) }
        } label: {
            Image(systemName: symbol)
                .contentTransition(.identity)
        }
        .iconButton(diameter: Self.diameter, glyph: Self.glyph, isOn: isOpen, isToggle: true, showsOnIndicator: false)
        .help(help(isOpen))
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityHint(hint(isOpen))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// The songs coming up, revealed under the volume row. It takes the width of its ink in the row, so the gaps either
// side of it are the gaps the eye sees.
private struct QueueButton: View {
    var body: some View {
        let toggle = DrawerToggle(
            drawer: .queue,
            symbol: "list.bullet",
            label: "Queue",
            help: { $0 ? "Hide queue" : "Show what plays next" },
            hint: { $0 ? "Hides the queue" : "Shows the songs coming up" },
            identifier: "orbit.queue"
        )
        toggle
            .inkAligned(.leading, toggle.ink, in: DrawerToggle.diameter)
            .inkAligned(.trailing, toggle.ink, in: DrawerToggle.diameter)
    }
}

// The glyph is the current device's kind; its name is in the tooltip, the spoken value and the list itself. Its
// ink ends at the trailing edge of a fixed slot on the margin, so every device's glyph lines up with the end of
// the seek row above and the queue button never moves when the device changes.
private struct DeviceButton: View {
    let device: PlaybackDevice?

    var body: some View {
        let toggle = DrawerToggle(
            drawer: .devices,
            symbol: device?.kind.symbol ?? "hifispeaker",
            label: "Devices",
            help: { DeviceButton.help(device: device, isOpen: $0) },
            value: device.map { "Playing on \($0.name)" } ?? "No device",
            hint: { $0 ? "Hides the device list" : "Shows Spotify Connect devices" },
            identifier: "orbit.devices"
        )
        toggle
            .inkAligned(.trailing, toggle.ink, in: DrawerToggle.diameter)
            .frame(width: OrbitTokens.Size.deviceSlot, alignment: .trailing)
    }

    static func help(device: PlaybackDevice?, isOpen: Bool) -> String {
        if isOpen { return "Hide devices" }
        guard let device else { return "Choose where Spotify plays" }
        return "Playing on \(device.name) · Choose where Spotify plays"
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
                message: "Orbit can't control Spotify",
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
