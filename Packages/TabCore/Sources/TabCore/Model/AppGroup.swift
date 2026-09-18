import Foundation

/// An app and its windows, MRU-ordered within the app.
///
/// This is the unit the app row renders. Grouping is the product: a flat window
/// list is a wall at 40 windows, and it is also slower to summon because every
/// tile must bind a thumbnail before first paint.
public struct AppGroup: Sendable, Hashable, Identifiable {
    public let app: AppRef
    /// Never empty — ``AppGrouping`` drops apps with no visible windows.
    public let windows: [WindowEntry]

    public var id: pid_t { app.pid }
    public var frontmost: WindowEntry { windows[0] }
    /// Whether dwell may reveal a window strip for this app.
    public var expandable: Bool { windows.count > 1 }

    public init(app: AppRef, windows: [WindowEntry]) {
        precondition(!windows.isEmpty, "AppGroup requires at least one window")
        self.app = app
        self.windows = windows
    }
}
