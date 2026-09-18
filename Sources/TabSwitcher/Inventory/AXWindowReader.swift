import ApplicationServices
import Foundation
import TabCore

/// What the Accessibility API knows about one window that ScreenCaptureKit does not:
/// an authoritative title, minimized state, and whether the app considers it its main
/// window. Also the only source that reports native macOS tabs at all — each tab
/// arrives as its own `AXWindow`.
struct AXWindow: Sendable {
    let windowID: CGWindowID?
    let title: String
    let isMinimized: Bool
    let isMain: Bool
    let frame: CGRect
    let element: AXElementBox
}

/// Reads `kAXWindowsAttribute` per process.
///
/// Every call is a synchronous Mach round-trip serviced on the *target's* main
/// thread, so this must never run on ours: one hung app would freeze the switcher.
/// Concurrency is bounded — 30 unresponsive apps must not spawn 30 blocked threads.
enum AXWindowReader {
    private static let maxConcurrent = 4

    static func isTrusted(prompting: Bool = false) -> Bool {
        // kAXTrustedCheckOptionPrompt is an unannotated mutable global, which Swift 6
        // strict concurrency rejects. Its value is this literal and always has been.
        let options = ["AXTrustedCheckOptionPrompt": prompting]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// - Returns: windows per pid. A pid missing from the result means AX gave us
    ///   nothing for it — denied, timed out, or genuinely windowless.
    static func readWindows(pids: [pid_t]) async -> [pid_t: [AXWindow]] {
        await withTaskGroup(of: (pid_t, [AXWindow]).self) { group in
            var remaining = pids[...]
            var results: [pid_t: [AXWindow]] = [:]

            func addNext() {
                guard let pid = remaining.popFirst() else { return }
                group.addTask { (pid, read(pid: pid)) }
            }
            for _ in 0..<min(maxConcurrent, pids.count) { addNext() }

            while let (pid, windows) = await group.next() {
                if !windows.isEmpty { results[pid] = windows }
                addNext()
            }
            return results
        }
    }

    private static func read(pid: pid_t) -> [AXWindow] {
        let app = AXElementBox.application(pid: pid)
        guard let raw: [AXUIElement] = app.attribute(kAXWindowsAttribute as String) else {
            return []
        }
        return raw.map { element in
            let box = AXElementBox(element)
            return AXWindow(
                windowID: box.cgWindowID,
                title: box.attribute(kAXTitleAttribute as String, as: String.self) ?? "",
                isMinimized: box.boolAttribute(kAXMinimizedAttribute as String),
                isMain: box.boolAttribute(kAXMainAttribute as String),
                frame: frame(of: box),
                element: box
            )
        }
    }

    private static func frame(of box: AXElementBox) -> CGRect {
        CGRect(
            origin: box.structAttribute(kAXPositionAttribute as String, .cgPoint, default: .zero),
            size: box.structAttribute(kAXSizeAttribute as String, .cgSize, default: .zero)
        )
    }
}
