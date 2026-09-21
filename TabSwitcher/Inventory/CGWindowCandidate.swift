import CoreGraphics
import Foundation

/// A window as the Window Server describes it, flattened to value types.
struct CGWindowCandidate: Sendable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let layer: Int
    let alpha: CGFloat
    let isOnScreen: Bool
}

/// Reads the Window Server's window list.
///
/// `CGWindowListCopyWindowInfo` is used rather than ScreenCaptureKit because it is
/// faster, is not deprecated (only `CGWindowListCreateImage` was removed), and needs
/// no Screen Recording grant for geometry — so the switcher still works when
/// thumbnails do not. Titles are the one field that grant gates, and those come from
/// accessibility anyway.
enum CGWindowList {

    /// Surfaces below this are decoration and above are menus, panels and overlays.
    private static let normalLayer = 0
    /// Smaller than this and it is a helper surface, not something a person switches to.
    private static let minimumSize = CGSize(width: 100, height: 100)
    /// Fully transparent surfaces are scaffolding the app never shows.
    private static let minimumAlpha: CGFloat = 0.01

    /// Diagnostic only: every surface with its attributes and whether it survived the
    /// filter. The filter is the most likely place for a window to go missing, so it
    /// has to be inspectable without a debugger.
    static func audit() -> [(candidate: CGWindowCandidate, passed: Bool, reason: String)] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let alpha = entry[kCGWindowAlpha as String] as? CGFloat ?? 1
            let frame = CGRect(
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
            )
            let candidate = CGWindowCandidate(
                id: id, pid: pid,
                title: entry[kCGWindowName as String] as? String ?? "",
                frame: frame, layer: layer, alpha: alpha,
                isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            )
            let reason: String
            if pid == ownPID { reason = "own process" }
            else if layer != normalLayer { reason = "layer \(layer)" }
            else if alpha <= minimumAlpha { reason = "alpha \(alpha)" }
            else if frame.width < minimumSize.width || frame.height < minimumSize.height {
                reason = "size \(Int(frame.width))x\(Int(frame.height))"
            } else { reason = "" }
            return (candidate, reason.isEmpty, reason)
        }
    }

    static func candidates() -> [CGWindowCandidate] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return raw.compactMap { entry -> CGWindowCandidate? in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  pid != ownPID,
                  layer == normalLayer
            else { return nil }

            let alpha = entry[kCGWindowAlpha as String] as? CGFloat ?? 1
            guard alpha > minimumAlpha else { return nil }

            let frame = CGRect(
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
            )
            guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else { return nil }

            return CGWindowCandidate(
                id: id,
                pid: pid,
                title: entry[kCGWindowName as String] as? String ?? "",
                frame: frame,
                layer: layer,
                alpha: alpha,
                isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            )
        }
    }
}
