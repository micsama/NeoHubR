import NeoHubLib
import ServiceManagement

@MainActor
extension AppSettingsStore {
    var launchAtLogin: Bool {
        get {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                log.error("Failed to toggle launch at login: \(error)")
            }
        }
    }
}
