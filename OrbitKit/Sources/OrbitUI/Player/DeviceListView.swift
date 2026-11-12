import OrbitCore
import OrbitEngine
import SwiftUI

// Spotify Connect devices, revealed in place under the player's volume row by the device button. Restricted
// devices are listed but disabled with the reason, a transfer shows progress on its row, and a failed transfer
// stays marked until the next attempt. Choosing a device closes the list once Spotify has moved; choosing the
// current one simply closes it. The list reports its height so the surface grows by exactly that much.
struct DeviceListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(AccountStore.self) private var account
    @Environment(PanelNavigator.self) private var navigator
    @Environment(\.orbitTheme) private var theme
    @State private var failure: (deviceID: String, error: OrbitError)?
    @State private var retained: [PlaybackDevice]?

    var body: some View {
        content
            .padding(.top, OrbitTokens.Spacing.s)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigator.recordDrawerHeight($0, for: .devices) }
            .onChange(of: library.devices.value, initial: true) { _, value in
                if let value { retained = value }
            }
            .task { await library.loadDevices() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Devices")
    }

    @ViewBuilder
    private var content: some View {
        switch account.authState {
        case .unknown:
            SkeletonRows(count: 2)
        case .signedOut:
            DrawerMessage(
                symbol: "person.crop.circle.badge.plus",
                title: "Connect Spotify to switch devices",
                action: StateAction(title: "Connect") { Task { await account.signIn() } }
            )
        case .authorizing:
            DrawerMessage(symbol: "safari", title: "Finish signing in in your browser")
        case .signedIn:
            devices
        }
    }

    @ViewBuilder
    private var devices: some View {
        switch library.devices.retaining(retained) {
        case .idle, .loading:
            SkeletonRows(count: 2)
        case .failed(let error):
            DrawerMessage(
                symbol: "exclamationmark.triangle",
                title: error.message,
                detail: error.recoveryHint,
                action: StateAction(title: "Try Again") { Task { await library.loadDevices() } }
            )
        case .loaded(let devices) where devices.isEmpty:
            DrawerMessage(
                symbol: "hifispeaker.2",
                title: "No devices found",
                detail: "Open Spotify on a phone, speaker or computer.",
                action: StateAction(title: "Refresh") { Task { await library.loadDevices() } }
            )
        case .loaded(let devices):
            let rows = ScrollView {
                VStack(spacing: OrbitTokens.Spacing.xxs) {
                    ForEach(devices) { device in
                        row(device)
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            if devices.count > OrbitTokens.Size.deviceListVisibleRows {
                rows.frame(height: Self.height(rows: OrbitTokens.Size.deviceListVisibleRows))
            } else {
                rows.frame(height: Self.height(rows: devices.count)).scrollDisabled(true)
            }
        }
    }

    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * OrbitTokens.Size.rowHeight + CGFloat(max(0, rows - 1)) * OrbitTokens.Spacing.xxs
    }

    private func row(_ device: PlaybackDevice) -> some View {
        let isActive = playback.snapshot.device.map { $0.id == device.id } ?? device.isActive
        return DeviceRow(
            device: device,
            isActive: isActive,
            isPending: playback.pendingIntents.contains(.transfer(deviceID: device.id)),
            failure: failure?.deviceID == device.id ? failure?.error : nil
        ) {
            isActive ? close() : transfer(to: device)
        }
    }

    private func transfer(to device: PlaybackDevice) {
        failure = nil
        Task {
            await playback.transfer(to: device)
            if let error = playback.lastError {
                withAnimation(theme.animation(OrbitTokens.Motion.content)) { failure = (device.id, error) }
            } else {
                close()
                await library.loadDevices()
            }
        }
    }

    private func close() {
        withAnimation(theme.animation(OrbitTokens.Motion.content)) { navigator.close(.devices) }
    }
}

// A drawer's empty, error and signed-out states: one compact line with an action, so a drawer never grows into
// a full-screen message beneath the player.
struct DrawerMessage: View {
    let symbol: String
    let title: String
    var detail: String?
    var action: StateAction?

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.l) {
            Image(systemName: symbol)
                .font(.system(size: OrbitTokens.Icon.transport - 1, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: OrbitTokens.Size.rowArtwork)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(OrbitTokens.Typography.rowTitle)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(OrbitTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.perform)
                    .capsuleButton()
            }
        }
        .padding(.horizontal, OrbitTokens.Spacing.m)
        .frame(minHeight: OrbitTokens.Size.rowHeight)
        .accessibilityElement(children: .combine)
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
        .disabled(device.isRestricted || isPending)
        .accessibilityLabel("\(device.name), \(statusText)")
        .accessibilityHint(isActive ? "Closes the device list" : "Plays on this device")
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
