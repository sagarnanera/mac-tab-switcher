import ApplicationServices
import Foundation

/// Decides whether an accessibility element is a window a person would switch to.
///
/// There is no clean predicate for this, and pretending otherwise is how switchers end
/// up listing tooltips. Measured on macOS 27, every app emits several full-width
/// strips at the origin and a square helper surface; browsers and Electron apps add
/// more. The Window Server list culls most by layer, alpha and size — this is the
/// second gate, on the accessibility side, where subrole is available.
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

    /// A window with no title from either source cannot be labelled in the UI, and in
    /// practice is always one of the helper surfaces above. Kept only when
    /// accessibility vouches for it, since AX sometimes has a title the Window Server
    /// list lacks.
    static func isRenderable(title: String, corroboratedByAX: Bool) -> Bool {
        !title.isEmpty || corroboratedByAX
    }
}
