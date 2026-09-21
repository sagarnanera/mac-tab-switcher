import Foundation

/// When resting on an app reveals its windows.
///
/// Progressive disclosure is the product's whole differentiator, and the timing is
/// the part most likely to be wrong, so it lives behind one configurable policy that
/// can be tuned from measurements rather than scattered `asyncAfter` calls.
public struct DwellPolicy: Sendable, Equatable {

    public enum Mode: Sendable, Equatable {
        /// Reveal after resting for `duration`.
        case delayed(Duration)
        /// Reveal as soon as an expandable app is selected.
        case instant
        /// Never reveal on its own; ↓ and hover are the only ways in.
        case manual
    }

    public var mode: Mode

    public init(mode: Mode = .delayed(.milliseconds(500))) {
        self.mode = mode
    }

    public static let `default` = DwellPolicy()

    /// Nil means "do not arm a timer": either dwell is manual, or the reveal should
    /// happen immediately and the caller should feed `dwellElapsed` straight back.
    public var delay: Duration? {
        switch mode {
        case .delayed(let duration): duration
        case .instant, .manual: nil
        }
    }

    public var firesAutomatically: Bool {
        switch mode {
        case .delayed, .instant: true
        case .manual: false
        }
    }

    public var isInstant: Bool {
        if case .instant = mode { return true }
        return false
    }

    /// Clamps user input to a range where the feature still works. Below ~150ms the
    /// strip flickers open while merely passing through an app; above ~2s nobody ever
    /// discovers the feature exists.
    public static func clampedDelay(milliseconds: Int) -> Duration {
        .milliseconds(min(2000, max(150, milliseconds)))
    }
}
