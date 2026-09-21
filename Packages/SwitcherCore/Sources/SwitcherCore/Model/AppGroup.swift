import Foundation

/// An app and its windows, ordered most-recently-used first.
///
/// This is the unit the app row renders, and the reason the switcher stays readable
/// at 40 windows where a flat list becomes a wall.
public struct AppGroup: Sendable, Hashable, Identifiable {
    public let app: AppRef
    /// Never empty — ``AppGrouping`` drops apps with no surviving windows.
    public let windows: [WindowEntry]

    public var id: pid_t { app.pid }
    public var frontmost: WindowEntry { windows[0] }
    /// Whether dwell may reveal a window strip for this app.
    public var isExpandable: Bool { windows.count > 1 }

    public init(app: AppRef, windows: [WindowEntry]) {
        precondition(!windows.isEmpty, "AppGroup requires at least one window")
        self.app = app
        self.windows = windows
    }
}

/// One enumeration pass: what the switcher should draw, and when it was gathered.
public struct WindowSnapshot: Sendable, Equatable {
    public let groups: [AppGroup]
    public let capturedAt: ContinuousClock.Instant

    public static let empty = WindowSnapshot(groups: [], capturedAt: .now)

    public init(groups: [AppGroup], capturedAt: ContinuousClock.Instant) {
        self.groups = groups
        self.capturedAt = capturedAt
    }
}

extension ContinuousClock.Instant {
    static var now: Self { ContinuousClock().now }
}
