import OrbitCore
import OrbitEngine
import SwiftUI

struct PillView: View {
    let playback: PlaybackCoordinator
    let preferences: Preferences
    let onExpand: () -> Void

    var body: some View {
        let snapshot = playback.snapshot
        HStack(spacing: OrbitTokens.Spacing.s) {
            if preferences.showsArtwork {
                ArtworkView(url: snapshot.track?.artworkURL, size: OrbitTokens.Size.pillArtwork, cornerRadius: OrbitTokens.Size.pillArtwork / 2)
            } else {
                Image(systemName: "music.note")
                    .frame(width: OrbitTokens.Size.pillArtwork)
            }
            Text(snapshot.track?.name ?? "Not playing")
                .font(OrbitTokens.Typography.pillTitle)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await playback.togglePlayPause() }
            } label: {
                Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: OrbitTokens.Size.controlIcon, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(snapshot.track == nil)
            .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("orbit.pill.playPause")
        }
        .padding(.horizontal, OrbitTokens.Spacing.m)
        .frame(width: OrbitTokens.Size.pill(preferences.pillSize).width, height: OrbitTokens.Size.pill(preferences.pillSize).height)
        .contentShape(.capsule)
        .onTapGesture(perform: onExpand)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Orbit")
        .accessibilityIdentifier("orbit.pill")
        .accessibilityAction(named: "Expand", onExpand)
    }
}
