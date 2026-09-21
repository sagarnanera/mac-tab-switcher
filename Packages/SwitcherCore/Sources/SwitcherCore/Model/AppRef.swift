import Foundation

/// A running application that owns windows.
public struct AppRef: Sendable, Hashable, Identifiable {
    /// Unique among live processes only. The OS reuses pids, so this is never
    /// persisted and never used as a cache key.
    public let pid: pid_t
    public let bundleID: String?
    public let name: String

    public var id: pid_t { pid }

    public init(pid: pid_t, bundleID: String?, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}
