import OrbitCore
import OrbitEngine
import SwiftUI

// Placeholder expanded surface that exercises the panel seam: transport, progress interpolation, a text field
// that needs key status, and a playlist list.
struct ExpandedCardView: View {
    let stores: OrbitStores
    let panel: PanelState
    let host: any PanelHost
    let preferences: Preferences

    @State private var filter = ""
    @State private var wantsSearchFocus = false
    @FocusState private var isSearchFocused: Bool

    private var playback: PlaybackCoordinator { stores.playback }

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitTokens.Spacing.m) {
            header
            nowPlaying
            progress
            transport
            searchField
            playlistList
            if let error = playback.lastError ?? stores.account.lastError {
                Text(error.message)
                    .font(OrbitTokens.Typography.secondary)
                    .foregroundStyle(OrbitTokens.Palette.warning)
                    .lineLimit(2)
                    .accessibilityIdentifier("orbit.card.error")
            }
        }
        .padding(OrbitTokens.Spacing.l)
        .frame(width: OrbitTokens.Size.expandedCard.width, height: OrbitTokens.Size.expandedCard.height, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orbit.card")
        .onChange(of: panel.isKeyWindow) { _, isKey in
            if isKey, wantsSearchFocus { isSearchFocused = true }
            if !isKey { wantsSearchFocus = false }
        }
    }

    private var header: some View {
        HStack {
            Text(playback.snapshot.context?.name ?? "Orbit")
                .font(OrbitTokens.Typography.sectionHeading)
                .foregroundStyle(OrbitTokens.Palette.secondaryText)
                .textCase(.uppercase)
            Spacer()
            Button {
                panel.collapse()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: OrbitTokens.Size.controlIcon, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
            .accessibilityIdentifier("orbit.card.collapse")
        }
        .contentShape(.rect)
        .panelDragGesture(host)
    }

    private var nowPlaying: some View {
        let track = playback.snapshot.track
        return HStack(spacing: OrbitTokens.Spacing.m) {
            if preferences.showsArtwork {
                ArtworkView(url: track?.artworkURL, size: OrbitTokens.Size.nowPlayingArtwork)
            }
            VStack(alignment: .leading, spacing: OrbitTokens.Spacing.xxs) {
                Text(track?.name ?? "Nothing playing")
                    .font(OrbitTokens.Typography.trackTitle)
                    .lineLimit(1)
                Text(track?.artistLine ?? "Pick a playlist below")
                    .font(OrbitTokens.Typography.secondary)
                    .foregroundStyle(OrbitTokens.Palette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: OrbitTokens.Motion.progressTick)) { context in
            let snapshot = playback.snapshot
            let duration = snapshot.track?.duration ?? 0
            let position = snapshot.position(at: context.date)
            VStack(spacing: OrbitTokens.Spacing.xs) {
                ProgressView(value: duration > 0 ? position / duration : 0)
                    .progressViewStyle(.linear)
                    .tint(OrbitTokens.Palette.accent(preferences.accent))
                HStack {
                    Text(Duration.seconds(position).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                }
                .font(OrbitTokens.Typography.caption)
                .foregroundStyle(OrbitTokens.Palette.secondaryText)
            }
        }
    }

    private var transport: some View {
        let snapshot = playback.snapshot
        return HStack(spacing: OrbitTokens.Spacing.xl) {
            control("shuffle", label: "Shuffle", id: "shuffle", active: snapshot.shuffle, enabled: snapshot.allows(.toggleShuffle)) {
                await playback.toggleShuffle()
            }
            control("backward.fill", label: "Previous", id: "previous", enabled: snapshot.allows(.skipPrevious)) {
                await playback.previous()
            }
            control(snapshot.isPlaying ? "pause.fill" : "play.fill", label: snapshot.isPlaying ? "Pause" : "Play", id: "playPause",
                    primary: true, enabled: snapshot.track != nil) {
                await playback.togglePlayPause()
            }
            control("forward.fill", label: "Next", id: "next", enabled: snapshot.allows(.skipNext)) {
                await playback.next()
            }
            control(snapshot.repeatMode == .track ? "repeat.1" : "repeat", label: "Repeat", id: "repeat",
                    active: snapshot.repeatMode != .off, enabled: snapshot.allows(.toggleRepeatContext)) {
                await playback.cycleRepeat()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func control(
        _ symbol: String,
        label: String,
        id: String,
        primary: Bool = false,
        active: Bool = false,
        enabled: Bool = true,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: primary ? OrbitTokens.Size.primaryControlIcon : OrbitTokens.Size.controlIcon, weight: .semibold))
                .foregroundStyle(active ? OrbitTokens.Palette.accent(preferences.accent) : OrbitTokens.Palette.primaryText)
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("orbit.card.\(id)")
    }

    private var searchField: some View {
        TextField("Find a playlist…", text: $filter)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .onSubmit { host.setAcceptsKeyboardInput(false) }
            .overlay {
                // The panel cannot take typing until the shell makes it key, so the first click asks for that.
                if !panel.isKeyWindow {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture {
                            wantsSearchFocus = true
                            host.setAcceptsKeyboardInput(true)
                        }
                }
            }
            .accessibilityIdentifier("orbit.card.search")
    }

    private var playlistList: some View {
        let playlists = (stores.library.playlists.value ?? []).filter {
            filter.isEmpty || $0.name.localizedStandardContains(filter)
        }
        return ScrollView {
            LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                ForEach(playlists) { playlist in
                    Button {
                        Task {
                            await playback.play(playlist: playlist)
                            if preferences.collapsesAfterAction, playback.lastError == nil { panel.collapse() }
                        }
                    } label: {
                        HStack(spacing: OrbitTokens.Spacing.s) {
                            ArtworkView(url: playlist.artworkURL, size: OrbitTokens.Size.playlistArtwork)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(playlist.name).font(OrbitTokens.Typography.rowTitle).lineLimit(1)
                                Text(playlist.ownerName)
                                    .font(OrbitTokens.Typography.secondary)
                                    .foregroundStyle(OrbitTokens.Palette.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if playback.pendingIntents.contains(.playContext(playlist.uri)) {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .padding(OrbitTokens.Spacing.xs)
                        .contentShape(.rect(cornerRadius: OrbitTokens.Radius.row))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("orbit.card.playlist.\(playlist.id)")
                }
            }
        }
        .scrollIndicators(.never)
    }
}
