import OrbitCore
import SwiftUI

struct BehaviorPane: View {
    @Bindable var preferences: Preferences
    let loginItem: LoginItem
    let panel: PanelController

    var body: some View {
        Form {
            Section {
                Toggle("Show the pill", isOn: $preferences.isPillVisible)
                Toggle("Keep above other windows", isOn: $preferences.alwaysOnTop)
                Toggle("Collapse after choosing music", isOn: $preferences.collapsesAfterAction)
            } header: {
                Text("Pill")
            } footer: {
                Text("With the pill hidden, open Orbit from its menu bar item or a global shortcut.")
                    .settingsFootnote()
            }

            Section {
                Toggle("Snap to screen edges", isOn: $preferences.snapsToEdges)
                Toggle("Dock at top center", isOn: $preferences.docksAtTopCenter)
                Toggle("Remember position", isOn: $preferences.remembersPosition)
                LabeledContent("Lost the pill?") {
                    Button("Reset Position") { panel.resetPosition() }
                }
            } header: {
                Text("Position")
            } footer: {
                Text("Orbit remembers a position for each display and moves the pill back when a display reconnects.")
                    .settingsFootnote()
            }

            Section("Hide automatically") {
                Toggle("While another app is full screen", isOn: $preferences.hidesInFullscreen)
                Toggle("When Spotify quits", isOn: $preferences.hidesWhenSpotifyQuits)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .disabled(!loginItem.isAvailable)
                if loginItem.needsApproval {
                    LabeledContent("Waiting for your approval in Login Items") {
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Startup")
            } footer: {
                if !loginItem.isAvailable {
                    Text("Not available in demo mode.").settingsFootnote()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsLayout.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
