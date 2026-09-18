import Foundation
import ScreenCaptureKit

/// A window as ScreenCaptureKit sees it, flattened to value types.
///
/// `SCWindow` never escapes the cache: it is not `Sendable`, and holding one past
/// the fetch that produced it is how you end up capturing a stale window.
struct ShareableWindow: Sendable, Hashable {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isOnScreen: Bool
    let layer: Int
}

/// Owns the one `SCShareableContent` fetch.
///
/// Two rules, both learned the hard way by other projects:
/// - **Never fetch during summon.** Enumerating shareable content at UI rates pegs
///   WindowServer. Fetch on launch and on window-change notifications; the hot path
///   reads the cached value.
/// - **Always race it against a timeout.** `SCShareableContent.current` sporadically
///   never returns (Apple FB12114396, still open). An un-raced await here wedges the
///   whole inventory forever.
actor ShareableContentCache {
    private var cached: [ShareableWindow] = []
    private var lastFetch: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    enum Failure: Error, CustomStringConvertible {
        case timedOut
        case denied(any Error)

        var description: String {
            switch self {
            case .timedOut: "ScreenCaptureKit did not respond within 2s (FB12114396)"
            case .denied(let error): "ScreenCaptureKit refused: \(error.localizedDescription)"
            }
        }
    }

    var windows: [ShareableWindow] { cached }

    /// Refetches unless the cache is younger than `maxAge`.
    @discardableResult
    func refresh(maxAge: Duration = .seconds(2)) async throws -> [ShareableWindow] {
        if let lastFetch, clock.now - lastFetch < maxAge { return cached }
        cached = try await fetch()
        lastFetch = clock.now
        return cached
    }

    private func fetch() async throws -> [ShareableWindow] {
        try await withThrowingTaskGroup(of: [ShareableWindow].self) { group in
            group.addTask {
                do {
                    // onScreenWindowsOnly: false — otherwise windows on other Spaces
                    // and fully occluded windows are never reported at all.
                    let content = try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: false)
                    return content.windows.compactMap { window in
                        guard let owner = window.owningApplication else { return nil }
                        return ShareableWindow(
                            windowID: window.windowID,
                            pid: owner.processID,
                            title: window.title ?? "",
                            frame: window.frame,
                            isOnScreen: window.isOnScreen,
                            layer: window.windowLayer
                        )
                    }
                } catch {
                    throw Failure.denied(error)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { return [] }
            return first
        }
    }
}
