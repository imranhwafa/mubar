import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for the menu bar app's "launch at login"
/// preference. UI binds via `isEnabled` (UserDefaults-backed reflection of
/// the live SMAppService status — kept in sync on demand).
enum LaunchAtLogin {
    static let storageKey = "preferences.launchAtLogin"

    /// Live registration state from the system. Cheap to call.
    static var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Reads the cached preference but reconciles with the system state.
    static var isEnabled: Bool {
        get { isRegistered }
        set { setEnabled(newValue) }
    }

    @discardableResult
    static func setEnabled(_ enable: Bool) -> Bool {
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            UserDefaults.standard.set(enable, forKey: storageKey)
            return true
        } catch {
            NSLog("[MUBAR] LaunchAtLogin failed: \(error.localizedDescription)")
            return false
        }
    }
}
