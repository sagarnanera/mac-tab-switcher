import CoreGraphics
import Testing
@testable import SwitcherCore

@Suite("OverlayStateMachine — summon")
struct SummonTests {

    @Test("lands on the second app so a tap toggles back to what you just left")
    func startsOnMRUSecond() {
        let state = Fixture.summoned()
        #expect(state.isVisible)
        #expect(state.selectedAppName == "Code")
    }

    @Test("with a single app, lands on it rather than nothing")
    func singleApp() {
        var state = OverlayState()
        _ = state.apply(.snapshotChanged(
            WindowSnapshot(groups: [Fixture.group("Finder", pid: 1, titles: ["Downloads"])], capturedAt: .now)
        ))
        _ = state.apply(.summon)
        #expect(state.selectedAppName == "Finder")
    }

    @Test("summoning while already visible changes nothing")
    func summonIsIdempotent() {
        var state = Fixture.summoned()
        _ = state.apply(.nextApp)
        let before = state
        let effects = state.apply(.summon)
        #expect(effects.isEmpty)
        #expect(state == before)
    }
}

@Suite("OverlayStateMachine — dwell")
struct DwellTests {

    @Test("dwell reveals the strip but does NOT move focus into it")
    func revealDoesNotFocus() {
        var state = Fixture.summoned()          // on Code, 3 windows
        _ = state.apply(.dwellElapsed)

        #expect(state.showsStrip)
        // Focus still on the app row: committing now must pick the app's frontmost
        // window, not a window the user never chose.
        #expect(state.selection == .grouped(app: 1, window: nil))
        #expect(state.selectedTitle == "api-server")
    }

    @Test("dwell arms only for apps with more than one window")
    func armsOnlyWhenExpandable() {
        var state = Fixture.summoned()
        let toSingleWindowApp = state.apply(.previousApp)   // Finder, 1 window
        #expect(toSingleWindowApp.contains(.cancelDwell))
        #expect(!toSingleWindowApp.contains(.armDwell))

        let toMultiWindowApp = state.apply(.nextApp)        // Code, 3 windows
        #expect(toMultiWindowApp.contains(.armDwell))
    }

    @Test("dwell on a single-window app does nothing even if fed")
    func dwellIgnoredWhenNotExpandable() {
        var state = Fixture.summoned()
        _ = state.apply(.previousApp)                       // Finder
        _ = state.apply(.dwellElapsed)
        #expect(!state.showsStrip)
    }

    @Test("arriving at a new app collapses its strip and re-arms dwell")
    func movingResetsDwell() {
        var state = Fixture.summoned()                      // Code, 3 windows
        _ = state.apply(.dwellElapsed)
        #expect(state.showsStrip)

        // Walk off the end of Code's windows and into Chrome.
        for _ in 0..<3 { _ = state.apply(.nextApp) }
        let effects = state.apply(.nextApp)

        #expect(state.selectedAppName == "Chrome")
        #expect(!state.showsStrip)
        #expect(effects.contains(.armDwell))
    }

    @Test("entering the strip cancels the pending dwell")
    func enterCancelsDwell() {
        var state = Fixture.summoned()
        let effects = state.apply(.enterStrip)
        #expect(effects.contains(.cancelDwell))
        #expect(state.showsStrip)
    }
}

@Suite("OverlayStateMachine — navigation")
struct NavigationTests {

    @Test("tapping without pausing walks apps and never enters a strip")
    func fastTappingStaysOnApps() {
        var state = Fixture.summoned()                      // Code
        _ = state.apply(.nextApp)
        #expect(state.selectedAppName == "Chrome")
        _ = state.apply(.nextApp)
        #expect(state.selectedAppName == "Finder")
        #expect(!state.showsStrip)
    }

    @Test("once dwell reveals the strip, the cycle key walks that app's windows")
    func cycleWalksStripAfterDwell() {
        var state = Fixture.summoned()                      // Code, 3 windows
        _ = state.apply(.dwellElapsed)

        _ = state.apply(.nextApp)
        #expect(state.selection == .grouped(app: 1, window: 0))
        #expect(state.selectedTitle == "api-server")

        _ = state.apply(.nextApp)
        #expect(state.selectedTitle == "tab-switcher")
    }

    @Test("walking off the end of a strip continues to the next app, never traps")
    func cycleFlowsOnPastLastWindow() {
        var state = Fixture.summoned()                      // Code, 3 windows
        _ = state.apply(.dwellElapsed)
        for _ in 0..<3 { _ = state.apply(.nextApp) }        // windows 0, 1, 2
        #expect(state.selectedTitle == "dotfiles")

        _ = state.apply(.nextApp)
        #expect(state.selectedAppName == "Chrome")
        #expect(state.selection == .grouped(app: 2, window: nil))
    }

    @Test("reversing off the front of a strip lands on the previous app")
    func reverseLeavesStripBackwards() {
        var state = Fixture.summoned()                      // Code
        _ = state.apply(.dwellElapsed)
        _ = state.apply(.nextApp)                           // into window 0
        #expect(state.selection == .grouped(app: 1, window: 0))

        _ = state.apply(.previousApp)
        #expect(state.selectedAppName == "Finder")
    }

    @Test("reverse steps back through windows before leaving the app")
    func reverseWalksStrip() {
        var state = Fixture.summoned()
        _ = state.apply(.dwellElapsed)
        for _ in 0..<3 { _ = state.apply(.nextApp) }        // on window 2
        _ = state.apply(.previousApp)
        #expect(state.selectedTitle == "tab-switcher")
    }

    @Test("a number jump selects that window directly and reveals the strip")
    func numberJump() {
        var state = Fixture.summoned()                      // Code, no strip yet
        let effects = state.apply(.selectWindow(2))

        #expect(state.selection == .grouped(app: 1, window: 2))
        #expect(state.selectedTitle == "dotfiles")
        #expect(state.showsStrip)
        #expect(effects.contains(.cancelDwell))
    }

    @Test("a number jump beyond the app's windows is ignored")
    func numberJumpOutOfRange() {
        var state = Fixture.summoned()
        #expect(state.apply(.selectWindow(9)).isEmpty)
        #expect(state.selection == .grouped(app: 1, window: nil))
    }

    @Test("apps wrap in both directions")
    func appWrapping() {
        var state = Fixture.summoned()          // index 1 of 3
        _ = state.apply(.nextApp)               // 2
        _ = state.apply(.nextApp)               // wraps to 0
        #expect(state.selectedAppName == "Finder")
        _ = state.apply(.previousApp)           // wraps back to 2
        #expect(state.selectedAppName == "Chrome")
    }

    @Test("down enters the strip, up leaves it but keeps it revealed")
    func enterAndLeave() {
        var state = Fixture.summoned()
        _ = state.apply(.enterStrip)
        #expect(state.selection == .grouped(app: 1, window: 0))

        _ = state.apply(.leaveStrip)
        #expect(state.selection == .grouped(app: 1, window: nil))
        // Still on screen: yanking it away would move the row under the user.
        #expect(state.showsStrip)
    }

    @Test("windows wrap within the strip")
    func windowWrapping() {
        var state = Fixture.summoned()
        _ = state.apply(.enterStrip)
        _ = state.apply(.previousWindow)        // wraps to last of 3
        #expect(state.selectedTitle == "dotfiles")
        _ = state.apply(.nextWindow)            // wraps to first
        #expect(state.selectedTitle == "api-server")
    }

    @Test("arrow from the app row steps into a revealed strip")
    func sidewaysEntersRevealedStrip() {
        var state = Fixture.summoned()
        _ = state.apply(.dwellElapsed)          // revealed, not entered
        _ = state.apply(.nextWindow)
        #expect(state.selection == .grouped(app: 1, window: 0))
    }

    @Test("arrow from the app row does nothing when no strip is revealed")
    func sidewaysWithoutStrip() {
        var state = Fixture.summoned()
        _ = state.apply(.nextWindow)
        #expect(state.selection == .grouped(app: 1, window: nil))
    }

    @Test("enterStrip on a single-window app is a no-op")
    func cannotEnterUnexpandable() {
        var state = Fixture.summoned()
        _ = state.apply(.previousApp)           // Finder
        let effects = state.apply(.enterStrip)
        #expect(effects.isEmpty)
        #expect(!state.showsStrip)
    }
}

@Suite("OverlayStateMachine — commit")
struct CommitTests {

    @Test("releasing on the app row activates that app's most recent window")
    func commitFromAppRow() {
        var state = Fixture.summoned()
        let effects = state.apply(.modifierReleased)
        #expect(effects.contains(.activate(Fixture.snapshot.groups[1].windows[0])))
        #expect(effects.contains(.hide))
        #expect(!state.isVisible)
    }

    @Test("a revealed but unentered strip still commits the app's frontmost window")
    func revealDoesNotChangeCommit() {
        var state = Fixture.summoned()
        _ = state.apply(.dwellElapsed)
        let effects = state.apply(.modifierReleased)
        #expect(effects.contains(.activate(Fixture.snapshot.groups[1].windows[0])))
    }

    @Test("releasing inside the strip activates that exact window")
    func commitFromStrip() {
        var state = Fixture.summoned()
        _ = state.apply(.enterStrip)
        _ = state.apply(.nextWindow)
        let effects = state.apply(.modifierReleased)
        #expect(effects.contains(.activate(Fixture.snapshot.groups[1].windows[1])))
    }

    @Test("escape restores the previous focus and activates nothing")
    func cancelActivatesNothing() {
        var state = Fixture.summoned()
        let effects = state.apply(.cancel)
        #expect(effects.contains(.restorePreviousFocus))
        #expect(effects.contains(.hide))
        #expect(!effects.contains { if case .activate = $0 { true } else { false } })
    }

    @Test("input is ignored while hidden")
    func ignoresInputWhenHidden() {
        var state = OverlayState()
        _ = state.apply(.snapshotChanged(Fixture.snapshot))
        #expect(state.apply(.nextApp).isEmpty)
        #expect(state.apply(.confirm).isEmpty)
        #expect(state.apply(.modifierReleased).isEmpty)
    }
}

@Suite("OverlayStateMachine — filtering")
struct FilterTests {

    @Test("typing takes over the session so a modifier release cannot commit")
    func typingMakesSticky() {
        var state = Fixture.summoned()
        _ = state.apply(.typed("a"))

        let effects = state.apply(.modifierReleased)
        #expect(effects.isEmpty)
        #expect(state.isVisible)
    }

    @Test("typing collapses the strip and switches to a flat list")
    func typingFlattens() {
        var state = Fixture.summoned()
        _ = state.apply(.dwellElapsed)
        _ = state.apply(.typed("d"))

        #expect(state.isFiltering)
        #expect(!state.showsStrip)
        if case .flat = state.selection {} else { Issue.record("expected a flat selection") }
    }

    @Test("filtering finds a window by title across apps")
    func findsByTitle() {
        var state = Fixture.summoned()
        for character in "dotf" { _ = state.apply(.typed(character)) }
        #expect(state.selectedTitle == "dotfiles")
    }

    @Test("deleting back to empty returns to the grouped view but stays sticky")
    func deleteReturnsToGrouped() {
        var state = Fixture.summoned()
        _ = state.apply(.typed("d"))
        _ = state.apply(.deleteBackward)

        #expect(!state.isFiltering)
        if case .grouped = state.selection {} else { Issue.record("expected a grouped selection") }
        // Still sticky: re-arming modifier-release mid-typing would be a trap.
        #expect(state.apply(.modifierReleased).isEmpty)
    }

    @Test("Enter commits the highlighted result while filtering")
    func confirmWhileFiltering() {
        var state = Fixture.summoned()
        for character in "dotf" { _ = state.apply(.typed(character)) }
        let effects = state.apply(.confirm)
        #expect(effects.contains { effect in
            if case .activate(let window) = effect { window.title == "dotfiles" } else { false }
        })
    }
}

@Suite("OverlayStateMachine — refresh during a session")
struct RefreshTests {

    @Test("selection stays pinned to the same window when the list re-sorts")
    func pinsSelectionAcrossRefresh() {
        var state = Fixture.summoned()
        _ = state.apply(.enterStrip)
        _ = state.apply(.nextWindow)
        let chosen = state.selectedWindow

        // Same windows, apps in a different order.
        _ = state.apply(.snapshotChanged(
            WindowSnapshot(groups: Fixture.snapshot.groups.reversed(), capturedAt: .now)
        ))
        #expect(state.selectedWindow == chosen)
    }

    @Test("selection clamps when the selected window disappears")
    func clampsWhenWindowGone() {
        var state = Fixture.summoned()
        _ = state.apply(.enterStrip)
        _ = state.apply(.nextWindow)

        _ = state.apply(.snapshotChanged(
            WindowSnapshot(groups: [Fixture.group("Code", pid: 2, titles: ["api-server"])], capturedAt: .now)
        ))
        #expect(state.selectedTitle == "api-server")
    }

    @Test("the overlay hides when every window disappears")
    func hidesWhenEmpty() {
        var state = Fixture.summoned()
        let effects = state.apply(.snapshotChanged(WindowSnapshot(groups: [], capturedAt: .now)))
        #expect(effects.contains(.hide))
        #expect(!state.isVisible)
    }
}

@Suite("OverlayStateMachine — refresh must not change level")
struct RefreshLevelTests {

    /// Two apps; Code has three windows whose ORDER changes between snapshots while
    /// each window keeps its identity.
    ///
    /// Ids are pinned to the title rather than to the position, because the ordinary
    /// fixture derives them from the index — which would renumber every window on a
    /// reorder and quietly test something else entirely.
    private func snapshot(codeOrder: [String]) -> WindowSnapshot {
        let ids: [String: CGWindowID] = ["a": 201, "b": 202, "c": 203]
        let code = AppGroup(
            app: Fixture.app(2, "Code"),
            windows: codeOrder.map { Fixture.window(ids[$0]!, pid: 2, title: $0) }
        )
        return WindowSnapshot(
            groups: [Fixture.group("Finder", pid: 1, titles: ["Downloads"]), code],
            capturedAt: .now
        )
    }

    @Test("a refresh that reorders windows leaves an app-row selection on the app row")
    func staysOnAppRow() {
        var state = OverlayState()
        _ = state.apply(.snapshotChanged(snapshot(codeOrder: ["a", "b", "c"])))
        _ = state.apply(.summon)
        // Summon lands on the second app, which is Code, on the app row.
        #expect(state.selection == .grouped(app: 1, window: nil))

        // The MRU moves "a" to third place, as it does whenever another window is used.
        _ = state.apply(.snapshotChanged(snapshot(codeOrder: ["b", "c", "a"])))

        // Previously this followed window "a" to index 2 and silently entered the strip,
        // so the next reveal began on the third tile.
        #expect(state.selection == .grouped(app: 1, window: nil))
    }

    @Test("a refresh still keeps a strip selection on the same window")
    func followsWindowInsideStrip() {
        var state = OverlayState()
        _ = state.apply(.snapshotChanged(snapshot(codeOrder: ["a", "b", "c"])))
        _ = state.apply(.summon)
        _ = state.apply(.enterStrip)
        _ = state.apply(.nextWindow)                      // on "b", index 1
        #expect(state.selectedWindow?.title == "b")

        _ = state.apply(.snapshotChanged(snapshot(codeOrder: ["c", "a", "b"])))
        // Same window, new index: the point of tracking by id rather than position.
        #expect(state.selectedWindow?.title == "b")
        #expect(state.selection == .grouped(app: 1, window: 2))
    }

    @Test("dwell after a reorder still reveals from the first tile")
    func revealStartsAtFirstTile() {
        var state = OverlayState()
        _ = state.apply(.snapshotChanged(snapshot(codeOrder: ["a", "b", "c"])))
        _ = state.apply(.summon)
        _ = state.apply(.snapshotChanged(snapshot(codeOrder: ["b", "c", "a"])))
        _ = state.apply(.dwellElapsed)
        _ = state.apply(.enterStrip)
        #expect(state.selection == .grouped(app: 1, window: 0))
    }
}
