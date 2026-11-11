import OrbitCore
import OrbitEngine
import SwiftUI

// Spotify Connect devices. Restricted devices are listed but disabled with the reason, a transfer shows progress
// on its row, and a failed transfer stays marked until the next attempt.
struct DeviceListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.orbitTheme) private var theme
    @State private var failure: (deviceID: String, error: OrbitError)?
    @State private var retained: [PlaybackDevice]?

    var body: some View {
        VStack(spacing: 0) {
            PanelTopBar { BackTitle(title: "Devices", subtitle: "Choose where Spotify plays") }
            AccountGate { content }
        }
        .onChange(of: library.devices.value, initial: true) { _, value in
            if let value { retained = value }
        }
        .task { await library.loadDevices() }
    }

    @ViewBuilder
    private var content: some View {
        switch library.devices.retaining(retained) {
        case .idle, .loading:
            SkeletonRows(count: 4)
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.top, OrbitTokens.Spacing.m)
                .frame(maxHeight: .infinity, alignment: .top)
        case .failed(let error):
            StatusMessage(error: error) { Task { await library.loadDevices() } }
                .frame(maxHeight: .infinity)
        case .loaded(let devices) where devices.isEmpty:
            StatusMessage(
                symbol: "hifispeaker.2",
                title: "No devices found",
                message: "Open Spotify on a phone, speaker or computer signed in to your account.",
                actions: [StateAction(title: "Refresh", symbol: "arrow.clockwise", isProminent: false) {
                    Task { await library.loadDevices() }
                }]
            )
            .frame(maxHeight: .infinity)
        case .loaded(let devices):
            ScrollView {
                LazyVStack(spacing: OrbitTokens.Spacing.xxs) {
                    ForEach(devices) { device in
                        DeviceRow(
                            device: device,
                            isActive: playback.snapshot.device.map { $0.id == device.id } ?? device.isActive,
                            isPending: playback.pendingIntents.contains(.transfer(deviceID: device.id)),
                            failure: failure?.deviceID == device.id ? failure?.error : nil
                        ) {
                            transfer(to: device)
                        }
                    }
                }
                .padding(.horizontal, OrbitTokens.Spacing.m)
                .padding(.top, OrbitTokens.Spacing.m)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .safeAreaInset(edge: .bottom) {
                Text("Devices appear here while Spotify is open on them.")
                    .font(OrbitTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, OrbitTokens.Spacing.s)
            }
        }
    }

    private func transfer(to device: PlaybackDevice) {
        failure = nil
        Task {
            await playback.transfer(to: device)
            if let error = playback.lastError {
                withAnimation(theme.animation(OrbitTokens.Motion.content)) { failure = (device.id, error) }
            } else {
                await library.loadDevices()
            }
        }
    }
}

private struct DeviceRow: View {
    let device: PlaybackDevice
    let isActive: Bool
    let isPending: Bool
    let failure: OrbitError?
    let action: () -> Void

    @Environment(\.orbitTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: OrbitTokens.Spacing.l) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: OrbitTokens.Icon.transport - 1, weight: .medium))
                    .foregroundStyle(isActive ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: OrbitTokens.Size.rowArtwork, height: OrbitTokens.Size.rowArtwork)
                    .background {
                        Circle().fill(OrbitPalette.quietFill(contrast: theme.contrast))
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(OrbitTokens.Typography.rowTitle)
                        .lineLimit(1)
                    Text(statusText)
                        .font(OrbitTokens.Typography.caption)
                        .foregroundStyle(failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(OrbitPalette.warning))
                        .lineLimit(1)
                }
                Spacer(minLength: OrbitTokens.Spacing.s)
                if isPending {
                    ProgressView().controlSize(.mini)
                } else if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: OrbitTokens.Icon.regular, weight: .bold))
                        .foregroundStyle(theme.accent)
                } else if failure != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(OrbitPalette.warning)
                }
            }
            .padding(.horizontal, OrbitTokens.Spacing.m)
            .frame(height: OrbitTokens.Size.rowHeight)
        }
        .rowButton(isSelected: isActive)
        .disabled(device.isRestricted || isActive || isPending)
        .accessibilityLabel("\(device.name), \(statusText)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var statusText: String {
        if let failure { return "Couldn't connect · \(failure.message)" }
        if isPending { return "Connecting…" }
        if device.isRestricted { return "Can't be controlled from Orbit" }
        if isActive { return device.supportsVolume ? "Playing here" : "Playing here · No volume control" }
        return device.supportsVolume ? kindName : "\(kindName) · No volume control"
    }

    private var kindName: String {
        switch device.kind {
        case .computer: "Computer"
        case .smartphone: "Phone"
        case .tablet: "Tablet"
        case .speaker: "Speaker"
        case .television: "TV"
        case .automobile: "Car"
        case .other: "Device"
        }
    }
}
