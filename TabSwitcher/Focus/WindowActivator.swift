import AppKit
import ApplicationServices
import Foundation
import SwitcherCore

enum ActivationOutcome: Sendable, CustomStringConvertible {
    case landed
    case landedAfterRetry
    case failed(String)

    var description: String {
        switch self {
        case .landed: "landed"
        case .landedAfterRetry: "landed after retry"
        case .failed(let reason): "FAILED — \(reason)"
        }
    }

    var succeeded: Bool {
        if case .failed = self { return false }
        return true
    }
}

/// Raises one specific window of one specific application.
///
/// This is the whole product in one function, and it is harder than it looks. macOS 14
/// downgraded `NSRunningApplication.activate` to an advisory *request*, and the public
/// APIs raise an app but never a chosen window — which is precisely the gap this app
/// exists to fill.
///
/// The sequence, each step load-bearing:
/// 1. **Deminiaturize** if needed. A minimized window cannot be raised; it has to come
///    back first, and the app may also be hidden.
/// 2. **`_SLPSSetFrontProcessWithOptions`** (private) fronts the process *and* names
///    the window, which is what makes macOS follow it to another Space.
/// 3. **Synthetic click** to make the window key — fronting alone does not give it
///    keyboard focus.
/// 4. **`AXRaise` + `kAXMain`** orders it within the app's own window stack, so the app
///    itself agrees which window is in front.
/// 5. **Verify** against the frontmost app, retry once with a re-resolved element, then
///    report failure honestly rather than silently doing nothing.
///
/// Steps 2 and 3 are private API and degrade cleanly: without them the public path
/// still raises the app, just less reliably across Spaces.
@MainActor
final class WindowActivator {
    private let store: WindowStore
    private var previousFront: NSRunningApplication?

    init(store: WindowStore) {
        self.store = store
    }

    func rememberFront() {
        previousFront = NSWorkspace.shared.frontmostApplication
    }

    func restorePreviousFocus() {
        guard let previousFront,
              previousFront.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        previousFront.activate()
    }

    func activate(_ window: WindowEntry) async -> ActivationOutcome {
        guard let target = NSRunningApplication(processIdentifier: window.pid) else {
            return .failed("process \(window.pid) is gone")
        }
        var element = await store.element(for: window.id)

        if window.flags.contains(.minimized) || target.isHidden {
            restore(window, element: element, app: target)
        }

        raise(window, element: element, target: target)
        if await landed(window, on: target) {
            await store.noteActivation(pid: window.pid, windowID: window.id)
            return .landed
        }

        // A stale accessibility element is the usual cause — the app recreated its
        // window between the last discovery pass and now.
        element = reresolve(window)
        raise(window, element: element, target: target)
        if await landed(window, on: target) {
            await store.noteActivation(pid: window.pid, windowID: window.id)
            return .landedAfterRetry
        }

        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing"
        let hadElement = element != nil
        return .failed(
            "frontmost is \(front), wanted \"\(window.title)\" of "
            + "\(target.localizedName ?? "pid \(window.pid)") "
            + "(ax element: \(hadElement ? "yes" : "MISSING"), window id \(window.id))"
        )
    }

    // MARK: - Steps

    private func restore(_ window: WindowEntry, element: AXElement?, app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        element?.set(kAXMinimizedAttribute as String, kCFBooleanFalse)
    }

    private func raise(_ window: WindowEntry, element: AXElement?, target: NSRunningApplication) {
        // Cooperative activation: naming the app we are yielding from is what makes
        // macOS 14+ honour the request rather than treating it as advisory.
        NSApp.yieldActivation(to: target)

        let fronted = PrivateAPI.setFrontProcess(pid: window.pid, windowID: window.id)
        if fronted {
            PrivateAPI.makeKeyWindow(pid: window.pid, windowID: window.id)
        } else {
            target.activate()
        }

        element?.perform(kAXRaiseAction as String)
        element?.set(kAXMainAttribute as String, kCFBooleanTrue)
    }

    /// Accessibility writes are serviced asynchronously on the target's own main
    /// thread, so there is nothing to await. 150ms is long enough for a responsive app
    /// and short enough to retry inside one user-perceptible beat.
    ///
    /// Verifies the **window**, not just the app. Checking only the frontmost process
    /// reports success whenever the right app comes forward with the wrong window in
    /// front — which is precisely the failure this app exists to prevent, so it must
    /// not be the failure its own test cannot see.
    /// Bundle identifier macOS reports as frontmost mid Space transition. It is not a
    /// failure — it means the switch we asked for is still animating.
    private static let transitionBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.dock",
    ]

    private func landed(_ window: WindowEntry, on target: NSRunningApplication) async -> Bool {
        // Raising a window on another Space triggers a Space switch that takes far
        // longer than a same-Space raise — several hundred milliseconds of animation,
        // during which macOS reports loginwindow as frontmost. A single short check
        // read that as failure and fired a second activation into the middle of the
        // animation, which is why cross-Space switches appeared not to work at all.
        let deadline = ContinuousClock().now + .milliseconds(window.flags.contains(.otherSpace) ? 2000 : 600)
        let clock = ContinuousClock()

        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard let front = NSWorkspace.shared.frontmostApplication else { continue }
            if let bundleID = front.bundleIdentifier, Self.transitionBundleIDs.contains(bundleID) {
                continue                                  // still transitioning
            }
            guard front.processIdentifier == target.processIdentifier else {
                continue                                  // a different app is up; keep waiting
            }
            if focusedMatches(window) { return true }
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
            && focusedMatches(window)
    }

    /// Verifies the **window**, not just the app. Checking only the frontmost process
    /// reports success whenever the right app comes forward with the wrong window in
    /// front — precisely the failure this app exists to prevent.
    private func focusedMatches(_ window: WindowEntry) -> Bool {
        let app = AXElement.application(pid: window.pid)
        app.setMessagingTimeout(0.25)
        guard let focused = app.copyElement(kAXFocusedWindowAttribute as String) else {
            // Nothing to check against: trust the app-level result rather than loop on
            // a question that cannot be answered.
            return true
        }
        if let id = focused.windowID { return id == window.id }
        return focused.title == window.title
    }

    private func reresolve(_ window: WindowEntry) -> AXElement? {
        let app = AXElement.application(pid: window.pid)
        app.setMessagingTimeout(0.25)
        return app.elements(kAXWindowsAttribute as String).first { $0.windowID == window.id }
    }
}
