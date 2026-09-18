import AppKit
import ApplicationServices
import Foundation
import TabCore

enum FocusOutcome: Sendable, CustomStringConvertible {
    case landed
    case retried
    case failed(String)

    var description: String {
        switch self {
        case .landed: "landed"
        case .retried: "landed after retry"
        case .failed(let why): "FAILED — \(why)"
        }
    }

    var isSuccess: Bool {
        if case .failed = self { return false }
        return true
    }
}

/// Raises one specific window of one specific app.
///
/// This is the entire product in one function, and it is harder than it looks:
/// macOS 14 downgraded `NSRunningApplication.activate` to an advisory *request*, and
/// `activateIgnoringOtherApps` with it. The cooperative model requires naming the app
/// you are yielding *from*, which is why the previously-frontmost app is captured
/// before the overlay ever appears.
///
/// Sequence, in order, each step load-bearing:
/// 1. `yieldActivation` — tells AppKit we are handing activation away deliberately.
/// 2. `AXRaise` — orders the window within its app's own window stack. Without this
///    you get the app's last-frontmost window, not the one that was chosen.
/// 3. `kAXMain = true` — makes it the app's main window, so the app agrees.
/// 4. `activate(from:)` — brings the process forward, citing the source app.
/// 5. Verify, retry once, then report failure honestly rather than silently doing
///    nothing.
@MainActor
final class FocusController {
    private var previousFront: NSRunningApplication?

    func rememberFront() {
        previousFront = NSWorkspace.shared.frontmostApplication
    }

    func cancel() {
        guard let previousFront, previousFront.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        previousFront.activate(from: .current, options: [])
    }

    func commit(_ ref: WindowEntry, element: AXElementBox?) async -> FocusOutcome {
        guard let target = NSRunningApplication(processIdentifier: ref.pid) else {
            return .failed("process \(ref.pid) is gone")
        }

        raise(ref, element: element, target: target)
        if await landed(ref, on: target) { return .landed }

        // A stale AX element is the common cause. Re-resolving by window id is cheap
        // and fixes the case where the app recreated its window between passes.
        raise(ref, element: reresolve(ref) ?? element, target: target)
        if await landed(ref, on: target) { return .retried }

        return .failed("frontmost is \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing"), wanted \(target.localizedName ?? "pid \(ref.pid)")")
    }

    private func raise(_ ref: WindowEntry, element: AXElementBox?, target: NSRunningApplication) {
        NSApp.yieldActivation(to: target)
        if let element {
            element.perform(kAXRaiseAction as String)
            element.setAttribute(kAXMainAttribute as String, kCFBooleanTrue)
        }
        target.activate(from: .current, options: [])
    }

    /// AX writes are asynchronous from our side — the target app services them on its
    /// own main thread, so there is nothing to await. 150ms is long enough for a
    /// responsive app and short enough to retry within one user-perceptible beat.
    private func landed(_ ref: WindowEntry, on target: NSRunningApplication) async -> Bool {
        try? await Task.sleep(for: .milliseconds(150))
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    private func reresolve(_ ref: WindowEntry) -> AXElementBox? {
        let app = AXElementBox.application(pid: ref.pid)
        guard let raw: [AXUIElement] = app.attribute(kAXWindowsAttribute as String) else { return nil }
        return raw.map { AXElementBox($0) }.first { $0.cgWindowID == ref.windowID }
    }
}
