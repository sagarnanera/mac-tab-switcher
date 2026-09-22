import Foundation

/// How the overlay's chrome answers the three Accessibility display settings.
///
/// Numbers rather than colours and animations: the decisions are what matter and the
/// SwiftUI types they turn into are not. Keeping them here means the rules can be
/// asserted in a test, which is the only practical way to check them — every branch
/// below is unreachable on a machine whose Accessibility settings are at their
/// defaults, so a reviewer would otherwise have to change their own system to see one.
public struct AppearanceRules: Equatable, Sendable {
    /// System Settings → Accessibility → Display → Reduce transparency.
    public let reducesTransparency: Bool
    /// …→ Increase contrast.
    public let increasesContrast: Bool
    /// …→ Reduce motion.
    public let reducesMotion: Bool

    public init(reducesTransparency: Bool = false,
                increasesContrast: Bool = false,
                reducesMotion: Bool = false) {
        self.reducesTransparency = reducesTransparency
        self.increasesContrast = increasesContrast
        self.reducesMotion = reducesMotion
    }

    public static let `default` = AppearanceRules()

    // MARK: - Panel

    /// The fill is deliberately not a decision here.
    ///
    /// `.regularMaterial` already turns opaque on its own when transparency is reduced —
    /// AppKit does that for every material, and second-guessing it would mean
    /// reimplementing a system behaviour that also tracks appearance and wallpaper
    /// tinting. What the system does *not* supply is an edge, and a HUD that has lost
    /// its translucency has also lost the depth cue separating it from the window
    /// behind it. So the border varies and the fill does not.
    public var panelBorderOpacity: Double {
        if increasesContrast { return 0.9 }
        if reducesTransparency { return 0.35 }
        return 0.10
    }

    public var panelBorderWidth: Double { increasesContrast ? 1.5 : 1 }

    // MARK: - Selection

    /// The selection ring is drawn in two tones at every setting, including the
    /// defaults.
    ///
    /// Not an accessibility affordance but a correctness fix: the ring sits directly on
    /// a window screenshot, and an accent-blue ring on a blue screenshot is invisible to
    /// everyone. The outer halo is the window background colour — near-black in dark
    /// appearance, near-white in light — so whichever ring loses contrast against the
    /// thumbnail, the other one still holds the edge.
    public var selectionOuterWidth: Double { increasesContrast ? 6 : 5 }
    public var selectionInnerWidth: Double { increasesContrast ? 3.5 : 3 }
    public var selectionHaloOpacity: Double { increasesContrast ? 1 : 0.55 }

    /// Unselected tiles get an edge only when contrast is asked for. At the default
    /// setting the thumbnails' own content is enough to separate them, and a border on
    /// every tile competes with the one border that carries meaning.
    public var unselectedBorderOpacity: Double { increasesContrast ? 0.45 : 0 }

    // MARK: - Motion

    /// Seconds for the window strip's reveal, or nil for an instant swap.
    ///
    /// The strip appearing under the app row is startling the first few times, and a
    /// short fade is the difference between "revealed" and "flashed". It is also exactly
    /// the onset motion Reduce Motion exists to suppress, so it is removed rather than
    /// slowed — a longer fade is more motion, not less.
    public var stripRevealDuration: Double? { reducesMotion ? nil : 0.12 }

    // MARK: - Debug

    /// Parses `--demo-a11y=contrast,transparency,motion`; nil when the flag is absent.
    ///
    /// Exists so every branch above is reachable from a command line without changing
    /// the machine's own Accessibility settings — a poor thing to ask of a reviewer and
    /// an impossible thing to ask of CI.
    public static func fromCommandLine(_ arguments: [String]) -> AppearanceRules? {
        guard let argument = arguments.first(where: { $0.hasPrefix("--demo-a11y") }) else { return nil }
        let flags = Set(argument.split(separator: "=").dropFirst().joined().split(separator: ","))
        return AppearanceRules(
            reducesTransparency: flags.contains("transparency"),
            increasesContrast: flags.contains("contrast"),
            reducesMotion: flags.contains("motion")
        )
    }
}
