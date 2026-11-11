import AppKit
import OrbitCore
import OrbitEngine
import OrbitUI
import SwiftUI

struct SpotifyPane: View {
    let stores: OrbitStores
    @Bindable var preferences: Preferences

    private var account: AccountStore { stores.account }
    private var library: LibraryStore { stores.library }

    var body: some View {
        Form {
            accountSection
            localAppSection
            devicesSection
            pinnedSection
            problemsSection
            ClientIDSection(preferences: preferences)
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.paneWidth, height: SettingsLayout.spotifyPaneHeight)
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Status") {
                HStack(spacing: OrbitTokens.Spacing.s) {
                    if account.authState == .authorizing || account.authState == .unknown {
                        ProgressView().controlSize(.small)
                    }
                    Text(accountStatus)
                }
            }
            HStack {
                Spacer()
                switch account.authState {
                case .signedIn:
                    Button("Reconnect") { Task { await account.signIn() } }
                        .help("Authorize Orbit again, for example after changing the Client ID")
                    Button("Sign Out") { Task { await account.signOut() } }
                case .signedOut:
                    Button("Sign In…") { Task { await account.signIn() } }
                        .keyboardShortcut(.defaultAction)
                case .authorizing, .unknown:
                    EmptyView()
                }
            }
            if let error = account.lastError {
                ErrorRow(error: error, retry: { await account.refreshLocalStatus() }, signIn: { await account.signIn() }) {
                    account.dismissError()
                }
            }
        }
    }

    private var accountStatus: String {
        switch account.authState {
        case .unknown: "Checking…"
        case .signedOut: "Not signed in"
        case .authorizing: "Finish signing in in your browser"
        case .signedIn: "Signed in as \(account.profile?.displayName ?? account.profile?.id ?? "Spotify user")"
        }
    }

    private var localAppSection: some View {
        Section {
            LabeledContent("Spotify app") {
                Text(!account.isSpotifyInstalled ? "Not installed" : account.isSpotifyRunning ? "Running" : "Not running")
            }
            LabeledContent("Automation") {
                HStack(spacing: OrbitTokens.Spacing.s) {
                    Text(automationStatus)
                    switch account.automationPermission {
                    case .denied:
                        Button("Open Automation Settings") { RecoveryAction.openAutomationSettings() }
                    case .notDetermined:
                        Button("Allow…") { Task { await account.requestAutomationPermission() } }
                    case .granted, .requiresSpotifyRunning:
                        EmptyView()
                    }
                }
            }
        } header: {
            Text("Spotify on this Mac")
        } footer: {
            Text("Automation lets Orbit play, pause and skip in the Spotify app instantly, without going through Spotify's servers. Orbit never brings Spotify's window forward.")
                .settingsFootnote()
        }
    }

    private var automationStatus: String {
        switch account.automationPermission {
        case .granted: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not asked yet"
        case .requiresSpotifyRunning: "Checked when Spotify is running"
        }
    }

    private var devicesSection: some View {
        Section {
            Picker("Preferred device", selection: $preferences.preferredDevice) {
                Text("Whichever is active").tag(DeviceReference?.none)
                ForEach(deviceChoices, id: \.self) { device in
                    Text(device.name).tag(Optional(device))
                }
            }
            switch library.devices {
            case .idle, .loading:
                LabeledContent("Available devices") { ProgressView().controlSize(.small) }
            case .failed(let error):
                ErrorRow(error: error, retry: { await library.loadDevices() }, signIn: { await account.signIn() })
            case .loaded(let devices) where devices.isEmpty:
                Text("No devices are available. Open Spotify on a device to see it here.")
                    .foregroundStyle(.secondary)
            case .loaded(let devices):
                ForEach(devices) { device in
                    DeviceRow(device: device) { Task { await stores.playback.transfer(to: device) } }
                }
            }
        } header: {
            HStack {
                Text("Devices")
                Spacer()
                Button("Refresh") { Task { await library.loadDevices() } }
                    .buttonStyle(.link)
                    .disabled(!account.authState.isSignedIn || library.devices.isLoading)
            }
        }
    }

    // A saved device that is asleep or gone still shows, so the choice is not silently dropped.
    private var deviceChoices: [DeviceReference] {
        var choices = (library.devices.value ?? []).map { DeviceReference(id: $0.id, name: $0.name) }
        if let preferred = preferences.preferredDevice, !choices.contains(where: { $0.id == preferred.id }) {
            choices.append(DeviceReference(id: preferred.id, name: "\(preferred.name) (unavailable)"))
        }
        return choices
    }

    private var pinnedSection: some View {
        Section {
            if library.pinnedPlaylists.isEmpty {
                Text("Pin playlists to keep them at the top of the playlist picker.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(library.pinnedPlaylists.enumerated()), id: \.element.id) { index, playlist in
                PinnedRow(
                    playlist: playlist,
                    canMoveUp: index > 0,
                    canMoveDown: index < library.pinnedPlaylists.count - 1,
                    move: { offset in library.movePinned(fromOffsets: [index], toOffset: offset > 0 ? index + 2 : index - 1) },
                    unpin: { library.unpin(playlist) }
                )
            }
            Menu("Pin a Playlist") {
                ForEach((library.playlists.value ?? []).filter { !library.isPinned($0) }) { playlist in
                    Button(playlist.name) { library.pin(playlist) }
                }
            }
            .disabled((library.playlists.value ?? []).allSatisfy(library.isPinned))
            if let error = library.playlists.error {
                ErrorRow(error: error, retry: { await library.loadPlaylists() }, signIn: { await account.signIn() })
            }
        } header: {
            Text("Pinned playlists")
        }
    }

    @ViewBuilder
    private var problemsSection: some View {
        if let error = stores.playback.lastError {
            Section("Playback") {
                ErrorRow(error: error, retry: { await stores.playback.refresh() }, signIn: { await account.signIn() }) {
                    stores.playback.dismissError()
                }
            }
        }
    }
}

private struct ClientIDSection: View {
    @Bindable var preferences: Preferences
    @State private var draft = ""

    var body: some View {
        Section {
            TextField("Client ID", text: $draft, prompt: Text(builtInClientID == nil ? "Required" : "Use this copy's built-in ID"))
                .font(.body.monospaced())
                .onSubmit(save)
            HStack {
                Text(source).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Save", action: save).disabled(normalized(draft) == preferences.clientIDOverride)
            }
        } header: {
            Text("Spotify Client ID")
        } footer: {
            Text("To use your own Spotify app, create one in the Spotify Developer Dashboard with the redirect URI http://127.0.0.1:8888/callback and paste its Client ID here. Sign in again after changing it.")
                .settingsFootnote()
        }
        .onAppear { draft = preferences.clientIDOverride ?? "" }
    }

    private var builtInClientID: String? {
        CompositionRoot.resolveClientID(override: nil, bundle: .main)
    }

    private var source: String {
        if preferences.clientIDOverride != nil { return "Using your Client ID." }
        return builtInClientID == nil ? "No Client ID configured. Sign-in needs one." : "Using the Client ID built into this copy."
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        preferences.clientIDOverride = normalized(draft)
        draft = preferences.clientIDOverride ?? ""
    }
}

private struct ErrorRow: View {
    let error: OrbitError
    let retry: () async -> Void
    let signIn: () async -> Void
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitTokens.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(OrbitTokens.Palette.warning)
            VStack(alignment: .leading, spacing: OrbitTokens.Spacing.xxs) {
                Text(error.message)
                if let hint = error.recoveryHint {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let action = RecoveryAction(for: error) {
                Button(action.title) { perform(action) }
            }
            if let dismiss {
                Button("Dismiss", action: dismiss).buttonStyle(.link)
            }
        }
    }

    private func perform(_ action: RecoveryAction) {
        switch action {
        case .signIn: Task { await signIn() }
        case .retry: Task { await retry() }
        case .openAutomationSettings: RecoveryAction.openAutomationSettings()
        case .openSpotify: RecoveryAction.openSpotify()
        case .openDeveloperDashboard: NSWorkspace.shared.open(RecoveryAction.developerDashboardURL)
        }
    }
}

private struct DeviceRow: View {
    let device: PlaybackDevice
    let transfer: () -> Void

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            Image(systemName: device.kind.symbol)
                .frame(width: OrbitTokens.Size.playlistArtwork)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name)
                if device.isRestricted {
                    Text("Can't be controlled remotely").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if device.isActive {
                Text("Playing").foregroundStyle(.secondary)
            } else {
                Button("Play Here", action: transfer).disabled(device.isRestricted)
            }
        }
    }
}

private struct PinnedRow: View {
    let playlist: Playlist
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let unpin: () -> Void

    var body: some View {
        HStack(spacing: OrbitTokens.Spacing.s) {
            Text(playlist.name).lineLimit(1)
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .accessibilityLabel("Move \(playlist.name) up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .accessibilityLabel("Move \(playlist.name) down")
            Button(role: .destructive, action: unpin) { Image(systemName: "pin.slash") }
                .accessibilityLabel("Unpin \(playlist.name)")
        }
        .buttonStyle(.borderless)
    }
}

extension PlaybackDevice.Kind {
    var symbol: String {
        switch self {
        case .computer: "laptopcomputer"
        case .smartphone: "iphone"
        case .tablet: "ipad"
        case .speaker: "hifispeaker"
        case .television: "tv"
        case .automobile: "car"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}
