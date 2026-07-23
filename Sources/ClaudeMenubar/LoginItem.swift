import Foundation
import ServiceManagement

/// Thin wrapper over SMAppService for "launch at login".
///
/// Only functions when running from an installed .app bundle (e.g. in
/// /Applications). From a bare `swift run` binary, register() will typically
/// throw or report .notFound — handled gracefully by the caller.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns true on success. Never throws to the UI.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("LoginItem toggle failed: \(error.localizedDescription)")
            return false
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "not enabled"
        case .requiresApproval: return "requires approval in System Settings"
        case .notFound: return "unavailable (run from an installed app)"
        @unknown default: return "unknown"
        }
    }
}
