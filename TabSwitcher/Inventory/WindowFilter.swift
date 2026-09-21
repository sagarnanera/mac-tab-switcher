import ApplicationServices
import Foundation

/// Decides whether a surface is a window a person would switch to.
///
/// There is no clean predicate for this, and pretending otherwise is how switchers end
/// up listing tooltips. Measured on macOS 27, every app emits several full-width strips
/// at the origin plus square helper surfaces; the Window Server list culls most of
/// those by layer, alpha and size. This is the second gate, where richer evidence is
/// available.
enum WindowFilter {

    /// `AXFloatingWindow` is deliberately excluded: a floating panel passes a naive
    /// role check but is not switchable — Outlook's meeting reminder is one.
    private static let switchableSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    static func isSwitchable(_ window: AXElement) -> Bool {
        guard window.role == kAXWindowRole as String else { return false }
        if let subrole = window.subrole, switchableSubroles.contains(subrole) { return true }
        // Escape hatch: some apps use non-standard subroles for windows that plainly
        // are windows. Real window chrome is the giveaway.
        return window.hasCloseButton || window.hasMinimizeButton
    }

    /// What evidence is available to judge a surface by.
    ///
    /// This distinction exists because "untitled means junk" is only a valid rule while
    /// titles are actually obtainable. The Window Server withholds `kCGWindowName`
    /// entirely without the Screen Recording grant, and treating that as "every window
    /// is junk" empties the switcher — which is exactly what happened before this
    /// existed.
    enum Evidence {
        /// Accessibility described this window: subrole has already decided it is
        /// switchable, and its title is authoritative.
        case accessibility
        /// No accessibility, but titles are being returned — so an untitled surface
        /// really is a helper window.
        case titlesAvailable
        /// Neither. Judge on geometry alone and label with the app name. A slightly
        /// noisy list beats an empty one.
        case geometryOnly
    }

    static func isRenderable(title: String, evidence: Evidence) -> Bool {
        switch evidence {
        case .accessibility: true
        case .titlesAvailable: !title.isEmpty
        case .geometryOnly: true
        }
    }
}
