import Foundation
import ServiceManagement

/// Registers the app to start at login.
///
/// `SMAppService` replaced the login-items API in macOS 13 and needs no helper bundle
/// for the main app. The status is owned by the system, not by our preferences, so it
/// is read back rather than stored — a user can remove the login item in System
/// Settings and a cached copy of that flag would then be a lie.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Returns: an error message if the change failed, nil on success.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // Registering while already enabled throws, and a stale
                // "requiresApproval" state also needs a fresh register.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// True when macOS has the registration but the user has not approved it yet, in
    /// which case the app will not actually launch until they do.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
