import Foundation

/// Turns a flat window list into the app-grouped, MRU-ordered structure the
/// switcher renders.
///
/// Pure: no clocks, no I/O, no globals. See `AppGroupingSpecs.md`.
public enum AppGrouping {

    public struct Options: Sendable, Hashable {
        /// When false, windows the OS presents as tabs of one window collapse to a
        /// single entry, so Finder with 6 tabs contributes 1 row instead of 6.
        /// Default on: the tabs are genuinely separate destinations and AX already
        /// hands them to us as separate windows.
        public var groupNativeTabs: Bool
        /// When false, minimized windows are omitted entirely.
        public var includeMinimized: Bool

        public init(groupNativeTabs: Bool = true, includeMinimized: Bool = true) {
            self.groupNativeTabs = groupNativeTabs
            self.includeMinimized = includeMinimized
        }

        public static let `default` = Options()
    }

    /// - Parameters:
    ///   - windows: every window seen this pass, in any order.
    ///   - apps: known apps. A window whose pid is absent here is dropped — we will
    ///     not render a row we cannot label.
    ///   - appMRU: pids, most recently used first. Pids absent from it sort after
    ///     every pid present, preserving their relative order in `apps`.
    ///   - windowMRU: window ids, most recently used first. Same tail rule.
    /// - Returns: groups in app-MRU order; never contains an empty group.
    public static func group(
        windows: [WindowEntry],
        apps: [AppRef],
        appMRU: [pid_t] = [],
        windowMRU: [UInt32] = [],
        options: Options = .default
    ) -> [AppGroup] {

        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let appRank = rank(appMRU)
        let windowRank = rank(windowMRU)
        let appOrder = Dictionary(uniqueKeysWithValues: apps.enumerated().map { ($0.element.pid, $0.offset) })

        var buckets: [pid_t: [WindowEntry]] = [:]
        for window in windows {
            guard appsByPID[window.pid] != nil else { continue }
            if window.flags.contains(.minimized) && !options.includeMinimized { continue }
            if window.flags.contains(.nativeTab) && !options.groupNativeTabs {
                // Keep only the tab the app considers primary; the rest are hidden
                // behind it in the UI anyway when tabs are not broken out.
                guard window.flags.contains(.main) else { continue }
            }
            buckets[window.pid, default: []].append(window)
        }

        return buckets
            .map { pid, group in
                AppGroup(
                    app: appsByPID[pid]!,
                    windows: group.sorted { lhs, rhs in
                        order(lhs, rhs, rank: windowRank)
                    }
                )
            }
            .sorted { lhs, rhs in
                let l = appRank[lhs.app.pid]
                let r = appRank[rhs.app.pid]
                switch (l, r) {
                case let (l?, r?):  return l < r
                case (.some, nil):  return true
                case (nil, .some):  return false
                case (nil, nil):
                    return (appOrder[lhs.app.pid] ?? .max) < (appOrder[rhs.app.pid] ?? .max)
                }
            }
    }

    /// Within an app: MRU first, then the app's own main window, then title, then
    /// window id. The last two exist only so the order is total and therefore stable
    /// across passes — a list that reshuffles between summons destroys muscle memory.
    private static func order(_ lhs: WindowEntry, _ rhs: WindowEntry, rank: [UInt32: Int]) -> Bool {
        switch (rank[lhs.windowID], rank[rhs.windowID]) {
        case let (l?, r?) where l != r: return l < r
        case (.some, nil):              return true
        case (nil, .some):              return false
        default: break
        }
        if lhs.flags.contains(.main) != rhs.flags.contains(.main) {
            return lhs.flags.contains(.main)
        }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.windowID < rhs.windowID
    }

    private static func rank<T: Hashable>(_ mru: [T]) -> [T: Int] {
        Dictionary(mru.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
}
