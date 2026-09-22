import CoreGraphics
import Foundation

/// Where the selection currently sits.
public enum Selection: Sendable, Equatable {
    /// Browsing the app row. `window` is nil while focus is on the app itself and an
    /// index once the user has stepped down into that app's window strip.
    case grouped(app: Int, window: Int?)
    /// Filtering: one flat, ranked list, so app and window levels stop being distinct.
    case flat(Int)
}

public enum OverlayInput: Sendable, Equatable {
    case summon
    case nextApp
    case previousApp
    case nextWindow
    case previousWindow
    /// ↓ — reveal the strip if needed and step into it, without waiting for dwell.
    case enterStrip
    /// ↑ — step back to the app row. The strip stays revealed.
    case leaveStrip
    case dwellElapsed
    /// Jump straight to the Nth window of the selected app, 0-based.
    case selectWindow(Int)
    case modifierReleased
    case confirm
    case cancel
    case typed(Character)
    case deleteBackward
    case hover(app: Int, window: Int?)
    case snapshotChanged(WindowSnapshot)
}

public enum OverlayEffect: Sendable, Equatable {
    case show
    case hide
    case armDwell
    case cancelDwell
    case activate(WindowEntry)
    case restorePreviousFocus
    /// Windows now on screen whose thumbnails should be fetched, highest priority first.
    case wantThumbnails([WindowEntry])
}

/// The entire interaction model as a pure function of (state, input).
///
/// Nothing here knows about `NSPanel`, timers, or AppKit. The dwell timer is an
/// *effect* the host arms and whose expiry it feeds back as ``OverlayInput/dwellElapsed``,
/// which is what makes "does dwell fire when it should" a unit test rather than a
/// stopwatch and a pair of eyes.
///
/// See `OverlayStateMachineSpecs.md` for the rules and their rationale.
public struct OverlayState: Sendable, Equatable {
    public private(set) var isVisible: Bool = false
    public private(set) var groups: [AppGroup] = []
    public private(set) var selection: Selection = .grouped(app: 0, window: nil)
    public private(set) var isStripRevealed: Bool = false
    public private(set) var filter: String = ""
    /// Once sticky, releasing the modifier no longer commits. Set by typing: you
    /// cannot hold Option and type a query, so the first keystroke must take over.
    public private(set) var isSticky: Bool = false

    public init() {}

    // MARK: - Derived

    public var isFiltering: Bool { !filter.isEmpty }

    /// The flat, ranked result list. Empty unless filtering.
    public var results: [FuzzyRank.Result] {
        guard isFiltering else { return [] }
        return FuzzyRank.rank(groups: groups, query: filter)
    }

    public var selectedApp: AppGroup? {
        switch selection {
        case .grouped(let app, _):
            groups.indices.contains(app) ? groups[app] : nil
        case .flat(let index):
            results.indices.contains(index)
                ? groups.first { $0.app.pid == results[index].window.pid }
                : nil
        }
    }

    /// What pressing Enter or releasing the modifier right now would switch to.
    public var selectedWindow: WindowEntry? {
        switch selection {
        case .grouped(let app, let window):
            guard groups.indices.contains(app) else { return nil }
            let group = groups[app]
            guard let window else { return group.frontmost }
            return group.windows.indices.contains(window) ? group.windows[window] : group.frontmost
        case .flat(let index):
            return results.indices.contains(index) ? results[index].window : nil
        }
    }

    /// Whether the selected app's strip should currently be on screen. Revealed is not
    /// the same as focused: dwell reveals, ↓ focuses.
    public var showsStrip: Bool {
        guard !isFiltering, isStripRevealed, let app = selectedApp else { return false }
        return app.isExpandable
    }

    // MARK: - Reduce

    public mutating func apply(_ input: OverlayInput) -> [OverlayEffect] {
        switch input {
        case .snapshotChanged(let snapshot):
            return applySnapshot(snapshot)

        case .summon:
            guard !isVisible else { return [] }
            isVisible = true
            filter = ""
            isSticky = false
            isStripRevealed = false
            // Land on the second-most-recent app, so a tap-and-release toggles back to
            // what you were just doing — the single most common switch there is.
            selection = .grouped(app: groups.count > 1 ? 1 : 0, window: nil)
            return [.show] + dwellEffects() + [.wantThumbnails(visibleWindows())]

        case .nextApp:
            return advance(by: 1)

        case .previousApp:
            return advance(by: -1)

        case .selectWindow(let index):
            guard isVisible, !isFiltering, case .grouped(let app, _) = selection,
                  let group = selectedApp, group.windows.indices.contains(index) else { return [] }
            isStripRevealed = group.isExpandable
            selection = .grouped(app: app, window: index)
            return [.cancelDwell]

        case .nextWindow:
            return moveWindow(by: 1)

        case .previousWindow:
            return moveWindow(by: -1)

        case .enterStrip:
            guard case .grouped(let app, _) = selection,
                  let group = selectedApp, group.isExpandable else { return [] }
            isStripRevealed = true
            selection = .grouped(app: app, window: 0)
            return [.cancelDwell, .wantThumbnails(group.windows)]

        case .leaveStrip:
            guard case .grouped(let app, let window) = selection, window != nil else { return [] }
            // The strip stays revealed: it was already on screen, and yanking it away
            // on ↑ would make the row jump under a user who is still deciding.
            selection = .grouped(app: app, window: nil)
            return []

        case .dwellElapsed:
            guard case .grouped = selection, let group = selectedApp, group.isExpandable,
                  !isStripRevealed else { return [] }
            // Reveal only. Moving focus here would mean releasing the modifier switches
            // to a window the user never chose.
            isStripRevealed = true
            return [.wantThumbnails(group.windows)]

        case .modifierReleased:
            guard isVisible else { return [] }
            // Typing takes over the session: you cannot hold a modifier and type a
            // query, so a release mid-query must not commit.
            guard !isSticky else { return [] }
            return commit()

        case .confirm:
            guard isVisible else { return [] }
            return commit()

        case .cancel:
            guard isVisible else { return [] }
            reset()
            return [.cancelDwell, .hide, .restorePreviousFocus]

        case .typed(let character):
            guard isVisible else { return [] }
            isSticky = true
            filter.append(character)
            selection = .flat(0)
            isStripRevealed = false
            return [.cancelDwell, .wantThumbnails(topResults())]

        case .deleteBackward:
            guard isVisible, !filter.isEmpty else { return [] }
            filter.removeLast()
            if filter.isEmpty {
                // Back to the grouped view. Stay sticky — the user has already shown
                // they are typing, and re-arming modifier-release now would be a trap.
                selection = .grouped(app: 0, window: nil)
                return dwellEffects() + [.wantThumbnails(visibleWindows())]
            }
            selection = .flat(0)
            return [.wantThumbnails(topResults())]

        case .hover(let app, let window):
            guard isVisible, !isFiltering, groups.indices.contains(app) else { return [] }
            let changedApp = currentAppIndex != app
            selection = .grouped(app: app, window: window)
            if window != nil { isStripRevealed = true }
            guard changedApp else { return [] }
            isStripRevealed = window != nil
            return dwellEffects() + [.wantThumbnails(visibleWindows())]
        }
    }

    // MARK: - Transitions

    private mutating func applySnapshot(_ snapshot: WindowSnapshot) -> [OverlayEffect] {
        let previouslySelected = selectedWindow?.id
        groups = snapshot.groups

        guard isVisible else { return [] }
        if groups.isEmpty {
            reset()
            return [.cancelDwell, .hide]
        }
        // Keep the selection pinned to the same window across a refresh. A list that
        // re-sorts under the user mid-switch is worse than a slightly stale one.
        if let previouslySelected, let found = locate(previouslySelected) {
            selection = found
        } else {
            selection = clamped(selection)
        }
        return [.wantThumbnails(visibleWindows())]
    }

    /// The cycle key, and the heart of the interaction.
    ///
    /// Tap quickly and it walks apps. Pause on an app with several windows and dwell
    /// reveals its strip — after which the same key walks *through those windows* and
    /// then continues on to the next app.
    ///
    /// This deliberately gives the key two meanings, which an earlier design forbade on
    /// the grounds that a key whose meaning depends on invisible state cannot be
    /// pressed quickly. The state is not invisible: the meaning changes exactly when
    /// the strip appears on screen. What it buys is that the whole interaction is
    /// reachable by the hand already holding the modifier, instead of requiring the
    /// other hand to find an arrow key — which was the real cost, since speed is the
    /// entire point of a switcher.
    ///
    /// Walking off the end continues to the next app rather than wrapping inside it, so
    /// the user is never trapped in one app's windows with no way onward.
    private mutating func advance(by delta: Int) -> [OverlayEffect] {
        guard isVisible else { return [] }
        if isFiltering { return moveFlat(by: delta) }
        guard !groups.isEmpty else { return [] }

        if showsStrip, case .grouped(let app, let window) = selection, let group = selectedApp {
            let next = (window ?? -1) + delta
            if group.windows.indices.contains(next) {
                selection = .grouped(app: app, window: next)
                return [.cancelDwell]
            }
            if delta < 0, window == nil || window == 0 {
                // Stepping back off the front of the strip lands on the app row of the
                // previous app, not on this app's last window.
                return moveToApp(app - 1)
            }
            return moveToApp(app + delta.signum())
        }
        return moveToApp(currentAppIndex + delta)
    }

    private mutating func moveToApp(_ index: Int) -> [OverlayEffect] {
        let next = ((index % groups.count) + groups.count) % groups.count
        selection = .grouped(app: next, window: nil)
        // The strip belongs to the app being left, and arriving somewhere new re-arms
        // dwell rather than cascading straight into the next app's windows.
        isStripRevealed = false
        return dwellEffects() + [.wantThumbnails(visibleWindows())]
    }

    private mutating func moveWindow(by delta: Int) -> [OverlayEffect] {
        guard isVisible else { return [] }
        if isFiltering { return moveFlat(by: delta) }
        guard case .grouped(let app, let window) = selection, let group = selectedApp else { return [] }

        // Sideways from the app row with a revealed strip steps into it, so ←/→ does
        // the obvious thing rather than nothing.
        guard let window else {
            guard isStripRevealed, group.isExpandable else { return [] }
            selection = .grouped(app: app, window: delta > 0 ? 0 : group.windows.count - 1)
            return [.cancelDwell]
        }
        let count = group.windows.count
        selection = .grouped(app: app, window: (window + delta + count) % count)
        return []
    }

    private mutating func moveFlat(by delta: Int) -> [OverlayEffect] {
        let count = results.count
        guard count > 0 else { return [] }
        let current = if case .flat(let index) = selection { index } else { 0 }
        selection = .flat((current + delta + count) % count)
        return []
    }

    private mutating func commit() -> [OverlayEffect] {
        guard let window = selectedWindow else {
            reset()
            return [.cancelDwell, .hide, .restorePreviousFocus]
        }
        reset()
        return [.cancelDwell, .hide, .activate(window)]
    }

    private mutating func reset() {
        isVisible = false
        isStripRevealed = false
        filter = ""
        isSticky = false
        selection = .grouped(app: 0, window: nil)
    }

    // MARK: - Helpers

    private var currentAppIndex: Int {
        if case .grouped(let app, _) = selection { return app }
        return 0
    }

    private func dwellEffects() -> [OverlayEffect] {
        guard let app = selectedApp, app.isExpandable else { return [.cancelDwell] }
        return [.armDwell]
    }

    /// Windows whose tiles are on screen right now, most important first.
    private func visibleWindows() -> [WindowEntry] {
        guard !isFiltering else { return topResults() }
        var wanted = groups.map(\.frontmost)
        if showsStrip, let app = selectedApp {
            wanted = app.windows + wanted
        }
        return wanted
    }

    private func topResults(limit: Int = 24) -> [WindowEntry] {
        results.prefix(limit).map(\.window)
    }

    /// Where a window now sits, so a refresh can keep the selection on the same thing
    /// rather than on the same index.
    ///
    /// Which *level* the selection is on is preserved separately, and deliberately. On
    /// the app row the selection means "this app", and the window it happens to resolve
    /// to — the app's first — is an implementation detail. Window order changes between
    /// refreshes as the MRU updates, so following the window would silently move the
    /// selection down into the strip and land it on whichever index that window drifted
    /// to. That is what made a reveal sometimes start at the second or third tile.
    private func locate(_ id: CGWindowID) -> Selection? {
        for (appIndex, group) in groups.enumerated() {
            guard let windowIndex = group.windows.firstIndex(where: { $0.id == id }) else { continue }
            if case .grouped(_, let selected) = selection, selected == nil {
                return .grouped(app: appIndex, window: nil)
            }
            return .grouped(app: appIndex, window: windowIndex)
        }
        return nil
    }

    private func clamped(_ selection: Selection) -> Selection {
        switch selection {
        case .grouped(let app, let window):
            let appIndex = min(app, groups.count - 1)
            guard let window else { return .grouped(app: appIndex, window: nil) }
            return .grouped(app: appIndex, window: min(window, groups[appIndex].windows.count - 1))
        case .flat(let index):
            return .flat(min(index, max(0, results.count - 1)))
        }
    }
}
