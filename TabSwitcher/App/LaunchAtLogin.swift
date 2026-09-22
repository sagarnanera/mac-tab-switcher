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
            } else {
                // `requiresApproval` must unregister too, which the original `== .enabled`
                // guard missed: macOS holds the registration and is only waiting on the
                // user, so switching the setting off while it is pending left the
                // registration in place while the toggle read as off. Stated as the two
                // cases that mean "there is nothing registered" rather than as a
                // double negative, so a future status is handled by unregistering, which
                // is the safe direction when the caller has asked for off.
                switch SMAppService.mainApp.status {
                case .notRegistered, .notFound: break
                default: try SMAppService.mainApp.unregister()
                }
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
