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
        static let hotkey = "hotkey"
        static let showsKeyboardHints = "showsKeyboardHints"
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
    /// The key hints along the bottom of the overlay. Useful while learning the
    /// gestures, noise once they are muscle memory.
    var showsKeyboardHints: Bool {
        didSet { defaults.set(showsKeyboardHints, forKey: Key.showsKeyboardHints) }
    }
    var hotkey: Hotkey {
        didSet {
            guard let data = try? JSONEncoder().encode(hotkey) else { return }
            defaults.set(data, forKey: Key.hotkey)
        }
    }
    /// Reflects the system's own login-item state rather than a stored copy: the user
    /// can remove the login item in System Settings, and a cached flag would then lie.
    var launchAtLogin: Bool {
        didSet {
            if let error = LaunchAtLogin.set(launchAtLogin) {
                launchAtLoginError = error
                launchAtLogin = LaunchAtLogin.isEnabled
            } else {
                launchAtLoginError = nil
            }
        }
    }
    var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var registered: [String: Any] = [Key.version: Self.currentVersion]
        for (key, value) in Self.defaults { registered[key] = value }
        defaults.register(defaults: registered)
        tileWidth = TileSizing.Metrics.clampedWidth(defaults.double(forKey: Key.tileWidth))
        dwellMilliseconds = defaults.integer(forKey: Key.dwellMilliseconds)
        dwellMode = defaults.string(forKey: Key.dwellMode) ?? "delayed"
        breakOutNativeTabs = defaults.bool(forKey: Key.breakOutNativeTabs)
        includeMinimized = defaults.bool(forKey: Key.includeMinimized)
        bestQualityThumbnails = defaults.bool(forKey: Key.bestQualityThumbnails)
        showsKeyboardHints = defaults.bool(forKey: Key.showsKeyboardHints)
        hotkey = (defaults.data(forKey: Key.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) }) ?? .default
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    /// Everything the user can change, in one place.
    ///
    /// Defined as a list rather than reassigning each property by hand so that adding a
    /// preference cannot silently leave a stale value behind on reset — a class of bug
    /// nobody notices until someone reports that "reset didn't reset it".
    private static let defaults: [(String, Any)] = [
        (Key.tileWidth, 220.0),
        (Key.dwellMilliseconds, 500),
        (Key.dwellMode, "delayed"),
        (Key.breakOutNativeTabs, true),
        (Key.includeMinimized, true),
        (Key.bestQualityThumbnails, true),
        (Key.showsKeyboardHints, true),
    ]

    /// Restores every preference to its shipped value.
    ///
    /// Launch at login is deliberately excluded: it lives in the system's login items,
    /// not in our defaults, and silently unregistering it would be a surprising side
    /// effect of a button labelled "restore defaults".
    func restoreDefaults() {
        for (key, _) in Self.defaults {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: Key.hotkey)

        tileWidth = TileSizing.Metrics.clampedWidth(defaults.double(forKey: Key.tileWidth))
        dwellMilliseconds = defaults.integer(forKey: Key.dwellMilliseconds)
        dwellMode = defaults.string(forKey: Key.dwellMode) ?? "delayed"
        breakOutNativeTabs = defaults.bool(forKey: Key.breakOutNativeTabs)
        includeMinimized = defaults.bool(forKey: Key.includeMinimized)
        bestQualityThumbnails = defaults.bool(forKey: Key.bestQualityThumbnails)
        showsKeyboardHints = defaults.bool(forKey: Key.showsKeyboardHints)
        hotkey = .default
    }

    /// Whether anything differs from the shipped values, so the reset control can be
    /// disabled when it would do nothing.
    var hasChangesFromDefaults: Bool {
        tileWidth != 220
            || dwellMilliseconds != 500
            || dwellMode != "delayed"
            || !breakOutNativeTabs
            || !includeMinimized
            || !bestQualityThumbnails
            || !showsKeyboardHints
            || hotkey != .default
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
