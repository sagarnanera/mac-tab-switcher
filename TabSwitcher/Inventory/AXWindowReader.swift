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
    private static func remoteWindows(pid: pid_t, probeLimit: UInt64 = 256) -> [AXElement] {
        guard PrivateAPI.has(.remoteToken) else { return [] }
        var found: [AXElement] = []
        var consecutiveMisses = 0

        for elementID in 0..<probeLimit {
            guard !AXResponsiveness.shared.isUnresponsive(pid) else { break }
            guard let raw = PrivateAPI.remoteElement(pid: pid, elementID: elementID) else {
                consecutiveMisses += 1
                if consecutiveMisses >= 24 { break }
                continue
            }
            let element = AXElement(raw, pid: pid)
            element.setMessagingTimeout(messagingTimeout)
            if element.role == kAXWindowRole as String {
                found.append(element)
                consecutiveMisses = 0
            } else {
                consecutiveMisses += 1
                if consecutiveMisses >= 24 { break }
            }
        }
        return found
    }
}
