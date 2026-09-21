import CoreGraphics
import Foundation

/// Turns a flat window list into the app-grouped, MRU-ordered structure the app row
/// renders. See `AppGroupingSpecs.md`.
public enum AppGrouping {

    public struct Options: Sendable, Hashable {
        /// When false, a native macOS tab set collapses to its main window, so Finder
        /// with 6 tabs contributes 1 row instead of 6.
        public var breakOutNativeTabs: Bool
        public var includeMinimized: Bool

        public init(breakOutNativeTabs: Bool = true, includeMinimized: Bool = true) {
            self.breakOutNativeTabs = breakOutNativeTabs
            self.includeMinimized = includeMinimized
        }

        public static let `default` = Options()
    }

    public static func group(
        windows: [WindowEntry],
        apps: [AppRef],
        appMRU: [pid_t] = [],
        windowMRU: [CGWindowID] = [],
        options: Options = .default
    ) -> [AppGroup] {
        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let appRank = rank(appMRU)
        let windowRank = rank(windowMRU)
        let appOrder = Dictionary(uniqueKeysWithValues: apps.enumerated().map { ($0.element.pid, $0.offset) })

        var buckets: [pid_t: [WindowEntry]] = [:]
        for window in windows {
            guard appsByPID[window.pid] != nil else { continue }
            if window.flags.contains(.minimized), !options.includeMinimized { continue }
            if window.flags.contains(.nativeTab), !options.breakOutNativeTabs,
               !window.flags.contains(.main) { continue }
            buckets[window.pid, default: []].append(window)
        }

        return buckets
            .map { pid, windows in
                AppGroup(app: appsByPID[pid]!, windows: windows.sorted { precedes($0, $1, rank: windowRank) })
            }
            .sorted { lhs, rhs in
                switch (appRank[lhs.app.pid], appRank[rhs.app.pid]) {
                case let (l?, r?): l < r
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): (appOrder[lhs.app.pid] ?? .max) < (appOrder[rhs.app.pid] ?? .max)
                }
            }
    }

    /// MRU, then the app's own main window, then title, then id. The last two exist
    /// only to make the order *total* and therefore identical across passes — a list
    /// that reshuffles between summons destroys the muscle memory that makes a
    /// switcher fast.
    private static func precedes(_ lhs: WindowEntry, _ rhs: WindowEntry, rank: [CGWindowID: Int]) -> Bool {
        switch (rank[lhs.id], rank[rhs.id]) {
        case let (l?, r?) where l != r: return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        if lhs.flags.contains(.main) != rhs.flags.contains(.main) { return lhs.flags.contains(.main) }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        return lhs.id < rhs.id
    }

    private static func rank<T: Hashable>(_ mru: [T]) -> [T: Int] {
        Dictionary(mru.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
}
