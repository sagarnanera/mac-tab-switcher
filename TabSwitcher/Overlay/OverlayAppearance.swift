import SwiftUI
import SwitcherCore

/// Turns `AppearanceRules` into the SwiftUI values the overlay actually applies.
///
/// The decisions live in the kernel, where they can be tested; this is only the
/// translation into styles and animations. Nothing here should ever contain an `if` —
/// if a new rule is needed, it belongs next to the others in `AppearanceRules`.
struct OverlayAppearance {
    let rules: AppearanceRules

    var increasesContrast: Bool { rules.increasesContrast }

    // MARK: - Panel

    var panelBorder: some ShapeStyle { Color.primary.opacity(rules.panelBorderOpacity) }
    var panelBorderWidth: Double { rules.panelBorderWidth }

    // MARK: - Selection

    /// Near-black in dark appearance and near-white in light, so the halo separates from
    /// the accent ring in either.
    var selectionHalo: some ShapeStyle {
        Color(nsColor: .windowBackgroundColor).opacity(rules.selectionHaloOpacity)
    }
    var selectionOuterWidth: Double { rules.selectionOuterWidth }
    var selectionInnerWidth: Double { rules.selectionInnerWidth }
    var unselectedBorderOpacity: Double { rules.unselectedBorderOpacity }

    // MARK: - Text

    /// Erased because the two branches are different concrete types, and a ternary over
    /// `HierarchicalShapeStyle` will not typecheck at the call sites.
    var secondaryText: AnyShapeStyle {
        rules.increasesContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }
    var tertiaryText: AnyShapeStyle {
        rules.increasesContrast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }
    /// Orange on a material is a warning; orange under Increase Contrast is a low
    /// contrast ratio. The symbol still carries the meaning.
    var warningText: AnyShapeStyle {
        rules.increasesContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.orange)
    }
    var dwellTrack: AnyShapeStyle {
        rules.increasesContrast ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    // MARK: - Motion

    var stripReveal: Animation? {
        rules.stripRevealDuration.map { .easeOut(duration: $0) }
    }

    var stripTransition: AnyTransition {
        rules.stripRevealDuration == nil ? .identity : .opacity
    }
}

private struct OverlayAppearanceOverrideKey: EnvironmentKey {
    static let defaultValue: OverlayAppearance? = nil
}

extension EnvironmentValues {
    /// Set by `--demo-a11y`, so the branches can be looked at without changing the
    /// machine's own Accessibility settings.
    var overlayAppearanceOverride: OverlayAppearance? {
        get { self[OverlayAppearanceOverrideKey.self] }
        set { self[OverlayAppearanceOverrideKey.self] = newValue }
    }

    /// Derived rather than stored, so a settings change SwiftUI already observes
    /// propagates without anything having to notice and republish it.
    var overlayAppearance: OverlayAppearance {
        overlayAppearanceOverride ?? OverlayAppearance(rules: AppearanceRules(
            reducesTransparency: accessibilityReduceTransparency,
            increasesContrast: colorSchemeContrast == .increased,
            reducesMotion: accessibilityReduceMotion
        ))
    }
}

extension OverlayAppearance {
    static func fromCommandLine() -> OverlayAppearance? {
        AppearanceRules.fromCommandLine(CommandLine.arguments).map(OverlayAppearance.init)
    }
}
