import Foundation
import Observation
import SwitcherCore

/// User settings, backed by `UserDefaults`.
///
/// Versioned from the start: a stored value whose meaning changes later needs a
/// migration path, and retrofitting one onto unversioned defaults means guessing what
/// an old value meant.
@MainActor
@Observable
final class Preferences {
    private enum Key {
        static let version = "prefsVersion"
        static let tileWidth = "tileWidth"
        static let dwellMilliseconds = "dwellMilliseconds"
        static let dwellMode = "dwellMode"
        static let breakOutNativeTabs = "breakOutNativeTabs"
        static let includeMinimized = "includeMinimized"
        static let bestQualityThumbnails = "bestQualityThumbnails"
    }

    static let currentVersion = 1

    private let defaults: UserDefaults

    var tileWidth: CGFloat {
        didSet { defaults.set(Double(tileWidth), forKey: Key.tileWidth) }
    }
    var dwellMilliseconds: Int {
        didSet { defaults.set(dwellMilliseconds, forKey: Key.dwellMilliseconds) }
    }
    /// "delayed", "instant" or "manual".
    var dwellMode: String {
        didSet { defaults.set(dwellMode, forKey: Key.dwellMode) }
    }
    var breakOutNativeTabs: Bool {
        didSet { defaults.set(breakOutNativeTabs, forKey: Key.breakOutNativeTabs) }
    }
    var includeMinimized: Bool {
        didSet { defaults.set(includeMinimized, forKey: Key.includeMinimized) }
    }
    var bestQualityThumbnails: Bool {
        didSet { defaults.set(bestQualityThumbnails, forKey: Key.bestQualityThumbnails) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.version: Self.currentVersion,
            Key.tileWidth: 220.0,
            Key.dwellMilliseconds: 500,
            Key.dwellMode: "delayed",
            Key.breakOutNativeTabs: true,
            Key.includeMinimized: true,
            Key.bestQualityThumbnails: true,
        ])
        tileWidth = TileSizing.Metrics.clampedWidth(defaults.double(forKey: Key.tileWidth))
        dwellMilliseconds = defaults.integer(forKey: Key.dwellMilliseconds)
        dwellMode = defaults.string(forKey: Key.dwellMode) ?? "delayed"
        breakOutNativeTabs = defaults.bool(forKey: Key.breakOutNativeTabs)
        includeMinimized = defaults.bool(forKey: Key.includeMinimized)
        bestQualityThumbnails = defaults.bool(forKey: Key.bestQualityThumbnails)
    }

    var dwellPolicy: DwellPolicy {
        switch dwellMode {
        case "instant": DwellPolicy(mode: .instant)
        case "manual": DwellPolicy(mode: .manual)
        default: DwellPolicy(mode: .delayed(DwellPolicy.clampedDelay(milliseconds: dwellMilliseconds)))
        }
    }

    var groupingOptions: AppGrouping.Options {
        .init(breakOutNativeTabs: breakOutNativeTabs, includeMinimized: includeMinimized)
    }

    var tileMetrics: TileSizing.Metrics {
        var metrics = TileSizing.Metrics.default
        metrics.preferredWidth = TileSizing.Metrics.clampedWidth(tileWidth)
        return metrics
    }
}
