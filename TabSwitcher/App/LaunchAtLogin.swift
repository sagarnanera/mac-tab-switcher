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

    /// Whether macOS holds a registration for this bundle, approved or not.
    ///
    /// `requiresApproval` counts: the registration exists and the system is merely
    /// waiting on the user. `notFound` and `notRegistered` both mean there is none —
    /// they differ only in whether macOS has ever held a record.
    ///
    /// Written as the two cases that mean *nothing is registered*, so a status Apple
    /// adds later is treated as registered. That is the safe direction for both callers:
    /// one unregisters it when asked to switch off, the other restores it afterwards.
    /// This lives here, and is the single definition, because the same question was
    /// previously asked three times in two different spellings that agreed only by
    /// coincidence on today's statuses.
    static func isRegistered(_ status: SMAppService.Status) -> Bool {
        status != .notRegistered && status != .notFound
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
            } else if isRegistered(SMAppService.mainApp.status) {
                // `requiresApproval` unregisters too, which the original `== .enabled`
                // guard missed: macOS holds the registration and is only waiting on the
                // user, so switching the setting off while it was pending left the
                // registration in place while the toggle read as off.
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
