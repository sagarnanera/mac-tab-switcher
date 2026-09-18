import Foundation

/// Identity of a running application that owns windows.
///
/// Carries only what the switcher renders and groups by. The `NSRunningApplication`
/// it was derived from stays in the app target — reading `icon`/`bundleURL` for a
/// process costs ~56ms the first time, so it is fetched off the main thread and
/// cached there, never re-derived here.
public struct AppRef: Sendable, Hashable, Identifiable {
    /// Process id. Unique among *live* processes only — the OS reuses pids, so this
    /// is never persisted and never used as a cache key.
    public let pid: pid_t
    /// Nil for processes with no bundle (rare: some helper and CLI-launched processes).
    public let bundleID: String?
    public let localizedName: String

    public var id: pid_t { pid }

    public init(pid: pid_t, bundleID: String?, localizedName: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}
