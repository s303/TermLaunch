import AppKit
import ServiceManagement

/// Launch at login via `SMAppService.mainApp`. The registration points at the
/// app's current location, so it is only enabled automatically for an installed
/// copy in /Applications, never for a dev build.
enum LoginItem {
    private static let defaultedKey = "didApplyLoginItemDefault"

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    static var needsApproval: Bool { status == .requiresApproval }

    /// On the first run of an installed copy, turn launch at login on. After
    /// that the user's choice (the menu toggle) is left alone.
    static func applyDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultedKey),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        defaults.set(true, forKey: defaultedKey)
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("TermLaunch: launch at login %@ failed: %@", enabled ? "enable" : "disable", "\(error)")
        }
        if enabled, needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
