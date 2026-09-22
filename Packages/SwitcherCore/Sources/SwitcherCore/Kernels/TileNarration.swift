import Foundation

/// What a screen reader says about one tile.
///
/// A kernel rather than a modifier on the view because the composition has real rules —
/// an untitled window still has to be identifiable, the state badges are drawn as icons
/// that announce nothing on their own, and position has to come from the caller rather
/// than from SwiftUI's own traversal order, which does not match the order the cycle key
/// moves through. Each of those is a thing that can be wrong, so each is a thing to test.
public enum TileNarration {

    /// - Parameters:
    ///   - index: zero-based position in its row.
    ///   - total: how many tiles are in that row.
    public static func label(
        window: WindowEntry,
        app: AppRef,
        index: Int,
        total: Int,
        windowCount: Int? = nil
    ) -> String {
        var parts: [String] = []

        // The app name leads. The title alone is ambiguous — "Untitled" or a bare file
        // name says nothing about where pressing Return will land you.
        parts.append(app.name)

        // A window with no title is common (palettes, some Electron windows) and must
        // still be distinguishable from its siblings, so it falls back to its position.
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(title.isEmpty ? "untitled window" : title)

        // The badges on the tile are icons, which announce nothing. Without these the
        // reason a window has no preview is invisible.
        if window.flags.contains(.minimized) { parts.append("minimized") }
        if window.flags.contains(.hidden) { parts.append("hidden") }
        if window.flags.contains(.fullScreen) { parts.append("full screen") }
        if window.flags.contains(.otherSpace) { parts.append("on another desktop") }

        // Said only when stepping in would reveal something, so it reads as an
        // invitation rather than trivia.
        if let windowCount, windowCount > 1 { parts.append("\(windowCount) windows") }

        // Last, because it is the least useful part and a screen reader user can
        // interrupt once they have heard enough.
        if total > 1 { parts.append("\(index + 1) of \(total)") }

        return parts.joined(separator: ", ")
    }

    /// Announced when the overlay appears. Says what opened and how to leave, because a
    /// panel that takes the keyboard without explaining itself is indistinguishable from
    /// the machine having locked up.
    public static func summary(appCount: Int, windowCount: Int) -> String {
        guard appCount > 0 else { return "Window switcher, no windows found. Escape to close." }
        return "Window switcher, \(windowCount) \(windowCount == 1 ? "window" : "windows") "
            + "across \(appCount) \(appCount == 1 ? "app" : "apps"). "
            + "Tab to move, Return to switch, Escape to close."
    }
}
