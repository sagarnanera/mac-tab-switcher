import AppKit
import ApplicationServices
import Foundation

/// One window as accessibility describes it, plus the live element needed to raise it.
struct AXWindow: @unchecked Sendable {
    let windowID: CGWindowID?
    let title: String
    let documentURL: String?
    let isMinimized: Bool
    let isMain: Bool
    let frame: CGRect
    let element: AXElement
}

/// Reads windows from applications over the accessibility API.
///
/// Concurrency is bounded rather than unbounded: each call blocks a thread on the
/// target's main thread, so fanning out across every running app would spawn a thread
/// per hung app. Four at a time keeps the pass parallel without that risk.
enum AXWindowReader {
    private static let maxConcurrent = 4
    /// Per-element cap on how long one call may block. The default is ~6s.
    private static let messagingTimeout: Float = 0.25

    static func read(pids: [pid_t], needingBruteForce: Set<pid_t> = []) async -> [pid_t: [AXWindow]] {
        await withTaskGroup(of: (pid_t, [AXWindow]).self) { group in
            var pending = pids[...]
            var results: [pid_t: [AXWindow]] = [:]

            func startNext() {
                guard let pid = pending.popFirst() else { return }
                group.addTask { (pid, read(pid: pid, bruteForce: needingBruteForce.contains(pid))) }
            }
            for _ in 0..<min(maxConcurrent, pids.count) { startNext() }

            while let (pid, windows) = await group.next() {
                if !windows.isEmpty { results[pid] = windows }
                startNext()
            }
            return results
        }
    }

    /// Diagnostic: which window ids the remote-token probe can reach for a process.
    static func probeRemoteWindowIDs(pid: pid_t) -> Set<CGWindowID> {
        Set(remoteWindows(pid: pid).compactMap { $0.windowID })
    }

    private static func read(pid: pid_t, bruteForce: Bool) -> [AXWindow] {
        guard !AXResponsiveness.shared.isUnresponsive(pid) else { return [] }
        let app = AXElement.application(pid: pid)
        app.setMessagingTimeout(messagingTimeout)

        var elements = app.elements(kAXWindowsAttribute as String)
        if bruteForce {
            let known = Set(elements.compactMap { $0.windowID })
            elements += remoteWindows(pid: pid).filter { element in
                element.windowID.map { !known.contains($0) } ?? false
            }
        }

        return elements.compactMap { element in
            element.setMessagingTimeout(messagingTimeout)
            guard WindowFilter.isSwitchable(element) else { return nil }
            return AXWindow(
                windowID: element.windowID,
                title: element.title,
                documentURL: element.documentURL,
                isMinimized: element.isMinimized,
                isMain: element.isMain,
                frame: element.frame,
                element: element
            )
        }
    }

    /// Windows on other Spaces are absent from `kAXWindowsAttribute` entirely — the
    /// accessibility API only ever describes the current Space. The workaround is to
    /// fabricate elements from a synthetic remote token and probe element ids.
    ///
    /// This is expensive (hundreds of cross-process calls) and so is **gated**: the
    /// caller only asks for it when the Window Server has proven a window exists that
    /// accessibility declined to hand over. Probing stops early on repeated failure,
    /// because a live process answers its low ids quickly.
    /// Probes the full range rather than stopping after a run of misses.
    ///
    /// An earlier version bailed after 24 consecutive misses, on the assumption that
    /// window elements cluster at low ids. They do not — a long-running app's windows
    /// sit well above its menus, buttons and other elements, so the early bail found
    /// nothing and every off-Space window ended up with no element to raise. The only
    /// bail now is an unresponsive process, which the breaker already tracks.
    ///
    /// Cost is ~1000 cheap cross-process calls, paid only for processes the Window
    /// Server has proven own a window accessibility is withholding.
    private static func remoteWindows(pid: pid_t, probeLimit: UInt64 = 1000) -> [AXElement] {
        guard PrivateAPI.has(.remoteToken) else { return [] }
        var found: [AXElement] = []

        for elementID in 0..<probeLimit {
            guard !AXResponsiveness.shared.isUnresponsive(pid) else { break }
            guard let raw = PrivateAPI.remoteElement(pid: pid, elementID: elementID) else { continue }
            let element = AXElement(raw, pid: pid)
            element.setMessagingTimeout(messagingTimeout)
            guard element.role == kAXWindowRole as String else { continue }
            found.append(element)
        }
        return found
    }
}
