import Observation
import ServiceManagement

// Launch at login is whatever the system says it is: the user can change it in System Settings › General ›
// Login Items at any time, so nothing is cached in Preferences and the status is re-read whenever it is shown.
// Nothing reads it before Settings opens, so launch never waits on ServiceManagement.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?
    // Demo builds are throwaway copies; registering one would leave a stale login item behind.
    let isAvailable: Bool
    private let readStatus: () -> SMAppService.Status

    init(isAvailable: Bool, readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status }) {
        self.isAvailable = isAvailable
        self.readStatus = readStatus
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        guard isAvailable else { return }
        status = readStatus()
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
