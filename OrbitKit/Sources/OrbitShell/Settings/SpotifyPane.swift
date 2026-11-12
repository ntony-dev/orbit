import AppKit
import OrbitCore
import OrbitEngine
import OrbitUI
import SwiftUI

struct SpotifyPane: View {
    let stores: OrbitStores
    @Bindable var preferences: Preferences
    // Re-read when a Web API pause ends, so the pause row goes away on time.
    @State private var now = Date()
    @State private var isRefreshingLibrary = false

    private var account: AccountStore { stores.account }
    private var library: LibraryStore { stores.library }

    var body: some View {
        Form {
            accountSection
            localAppSection
            devicesSection
            pinnedSection
            syncSection
            problemsSection
            ClientIDSection(preferences: preferences)
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.paneWidth, height: SettingsLayout.spotifyPaneHeight)
        .task(id: playback.webAPIPausedUntil) {
            now = Date()
            guard let until = playback.webAPIPausedUntil, until > now else { return }
            try? await Task.sleep(for: .seconds(until.timeIntervalSince(now)))
            now = Date()
        }
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Status") {
                HStack(spacing: SettingsLayout.spacing) {
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
            LabeledContent("Controlling") {
                Text(controlRoute)
            }
            LabeledContent("Automation") {
                HStack(spacing: SettingsLayout.spacing) {
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

    private var controlRoute: String {
        switch stores.playback.authority {
        case .local: "Spotify on this Mac"
        case .webAPI: stores.playback.snapshot.device.map { "\($0.name), through Spotify Connect" } ?? "Spotify Connect"
        case nil: "Nothing is playing"
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
                ForEach(deviceChoices, id: \.self) { choice in
                    Text(choice.title).tag(Optional(choice.reference))
                }
            }
            if case .missing(let device) = library.preferredDeviceStatus {
                Text("\(device.name) isn't available right now, so Orbit plays on whichever device is active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            switch library.devices {
            case .idle where !account.authState.isSignedIn:
                Text("Sign in to see the devices on your Spotify account.")
                    .foregroundStyle(.secondary)
            case .idle, .loading:
                LabeledContent("Available devices") { ProgressView().controlSize(.small) }
            case .failed(let error):
                ErrorRow(error: error, retry: { await library.loadDevices(force: true) }, signIn: { await account.signIn() })
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
                // Forced, because the cached list counts as fresh for a few seconds and Refresh would do nothing.
                Button("Refresh") { Task { await library.loadDevices(force: true) } }
                    .buttonStyle(.link)
                    .disabled(!account.authState.isSignedIn || library.devices.isLoading)
            }
        }
    }

    private var deviceChoices: [DeviceChoice] {
        DeviceChoice.choices(
            devices: library.devices.value ?? [],
            preferred: preferences.preferredDevice,
            status: library.preferredDeviceStatus
        )
    }

    private var pinnedSection: some View {
        Section {
            if library.pinnedPlaylists.isEmpty {
                Text("Pin playlists to keep them at the top of Orbit's library.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(library.pinnedPlaylists.enumerated()), id: \.element.id) { index, playlist in
                PinnedRow(
                    playlist: playlist,
                    isMissing: library.missingPlaylistIDs.contains(playlist.id),
                    canMoveUp: index > 0,
                    canMoveDown: index < library.pinnedPlaylists.count - 1,
                    move: { offset in library.movePinned(fromOffsets: [index], toOffset: offset > 0 ? index + 2 : index - 1) },
                    unpin: { library.unpin(playlist) }
                )
            }
            Menu("Pin a Playlist") {
                ForEach(pinnablePlaylists) { playlist in
                    Button(playlist.name) { library.pin(playlist) }
                }
            }
            .disabled(pinnablePlaylists.isEmpty)
            if let error = library.playlists.error {
                ErrorRow(error: error, retry: { await library.loadPlaylists(force: true) }, signIn: { await account.signIn() })
            }
        } header: {
            Text("Pinned playlists")
        }
    }

    private var syncSection: some View {
        Section {
            Picker("Check Spotify's servers", selection: $preferences.syncFrequency) {
                ForEach(SyncFrequency.allCases, id: \.self) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }
            LabeledContent("Library") {
                HStack(spacing: SettingsLayout.spacing) {
                    if isRefreshingLibrary { ProgressView().controlSize(.small) }
                    Button("Refresh Now") { Task { await refreshLibrary() } }
                        .disabled(!account.authState.isSignedIn || isRefreshingLibrary)
                }
            }
        } header: {
            Text("Synchronization")
        } footer: {
            Text("Playback in the Spotify app on this Mac shows up instantly either way. This sets how soon Orbit notices playback on your other devices; it never checks while hidden. Playlists refresh when you open Orbit, at most every few minutes.")
                .settingsFootnote()
        }
    }

    // Forced, because cached library data counts as fresh for a few minutes. Playlists the user has opened are
    // refetched too, so a change made in Spotify shows up without waiting for their cache to expire.
    private func refreshLibrary() async {
        isRefreshingLibrary = true
        defer { isRefreshingLibrary = false }
        let library = library
        let opened = (library.playlists.value ?? []).filter { library.playlistItems[$0.id]?.value != nil }
        let refetchesLikedSongs = library.savedTracks.value != nil
        await withDiscardingTaskGroup { group in
            group.addTask { await library.loadPlaylists(force: true) }
            group.addTask { await library.loadDevices(force: true) }
            if refetchesLikedSongs {
                group.addTask { await library.loadSavedTracks(force: true) }
            } else {
                group.addTask { await library.loadLikedSongsCount(force: true) }
            }
            for playlist in opened {
                group.addTask { await library.loadItems(for: playlist, force: true) }
            }
        }
    }

    // Liked Songs first, as in the library; it is not part of the playlist list Spotify returns.
    private var pinnablePlaylists: [Playlist] {
        ([library.likedSongs].compactMap(\.self) + (library.playlists.value ?? [])).filter { !library.isPinned($0) }
    }

    private var playback: PlaybackCoordinator { stores.playback }

    private static func isRateLimit(_ error: OrbitError) -> Bool {
        switch error {
        case .rateLimited, .quotaExceeded: true
        default: false
        }
    }

    @ViewBuilder
    private var problemsSection: some View {
        let pausedUntil = playback.webAPIPausedUntil.flatMap { $0 > now ? $0 : nil }
        // Rate limits are explained by the pause row; a failure already shown as the playback error is not repeated.
        let syncError = playback.syncError.flatMap { $0 == playback.lastError || Self.isRateLimit($0) ? nil : $0 }
        if playback.lastError != nil || syncError != nil || library.lastError != nil || pausedUntil != nil {
            Section {
                if let pausedUntil {
                    WebAPIPauseRow(until: pausedUntil)
                }
                if let error = playback.lastError {
                    ErrorRow(error: error, retry: { await playback.refresh() }, signIn: { await account.signIn() }) {
                        playback.dismissError()
                    }
                }
                // Background syncing failures never interrupt the player, so this is the one place they show.
                if let syncError {
                    ErrorRow(error: syncError, retry: { await playback.refresh() }, signIn: { await account.signIn() })
                }
                if let error = library.lastError {
                    // A failed one-off action such as adding to the queue has nothing to retry from here.
                    ErrorRow(error: error, retry: nil, signIn: { await account.signIn() }) {
                        library.dismissError()
                    }
                }
            } header: {
                Text("Problems")
            }
        }
    }
}

private struct ClientIDSection: View {
    @Bindable var preferences: Preferences
    @State private var draft = ""

    var body: some View {
        Section {
            LabeledContent("Client ID") {
                TextField("Client ID", text: $draft, prompt: Text(builtInClientID == nil ? "Required" : "Use this copy's built-in ID"))
                    .labelsHidden()
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .onSubmit(save)
            }
            HStack {
                Text(source).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Save", action: save).disabled(normalized(draft) == preferences.clientIDOverride)
            }
        } header: {
            Text("Spotify Client ID")
        } footer: {
            Text(verbatim: "To use your own Spotify app, create one in the Spotify Developer Dashboard with the redirect URI http://127.0.0.1:8888/callback and paste its Client ID here. Sign in again after changing it.")
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
    let retry: (() async -> Void)?
    let signIn: () async -> Void
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.spacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            VStack(alignment: .leading, spacing: SettingsLayout.tightSpacing) {
                Text(error.message)
                if let hint = error.recoveryHint {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let action = RecoveryAction(for: error), action != .retry || retry != nil {
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
        case .retry: Task { await retry?() }
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
        HStack(spacing: SettingsLayout.spacing) {
            Image(systemName: device.kind.symbol)
                .frame(width: SettingsLayout.rowIcon)
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

private struct WebAPIPauseRow: View {
    let until: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.spacing) {
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: SettingsLayout.tightSpacing) {
                Text("Spotify asked Orbit to slow down. Requests resume in \(Text(until, style: .relative)).")
                Text("Play, pause and skip keep working through the Spotify app on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PinnedRow: View {
    let playlist: Playlist
    let isMissing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let unpin: () -> Void

    var body: some View {
        HStack(spacing: SettingsLayout.spacing) {
            Text(playlist.name).lineLimit(1)
            if isMissing {
                Text("No longer in your library").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
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

extension SyncFrequency {
    var title: String {
        switch self {
        case .standard: "Automatically"
        case .reduced: "Less often"
        case .whileOpen: "Only while Orbit is open"
        }
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

// The preferred-device picker's rows. A saved device that is asleep or gone still shows, so the choice is not
// silently dropped, and a saved device Spotify now lists under a new ID keeps the saved reference as its tag so
// the picker still shows it selected.
struct DeviceChoice: Hashable {
    var reference: DeviceReference
    var title: String

    static func choices(devices: [PlaybackDevice], preferred: DeviceReference?, status: PreferredDeviceStatus) -> [DeviceChoice] {
        var choices = devices.map { DeviceChoice(reference: DeviceReference(id: $0.id, name: $0.name), title: $0.name) }
        switch status {
        case .notSet:
            break
        case .available(let device):
            if let preferred, let index = choices.firstIndex(where: { $0.reference.id == device.id }) {
                choices[index].reference = preferred
            }
        case .unverified(let reference):
            if !choices.contains(where: { $0.reference.id == reference.id }) {
                choices.append(DeviceChoice(reference: reference, title: reference.name))
            }
        case .missing(let reference):
            choices.append(DeviceChoice(reference: reference, title: "\(reference.name) (unavailable)"))
        }
        return choices
    }
}
