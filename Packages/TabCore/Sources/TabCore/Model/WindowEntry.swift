import CoreGraphics
import Foundation

/// One switchable window.
///
/// Named `WindowEntry`, not `WindowEntry`: Carbon exports a global `WindowEntry` type
/// that AppKit transitively re-exports, and the collision is unresolvable at every
/// use site without qualifying.
///
/// Deliberately holds no `AXUIElement`: this type lives in the pure core and must
/// stay `Sendable` and constructible in tests. The app target keeps a pid-keyed
/// side table of AX elements and re-resolves by ``windowNumber`` when one goes
/// stale (`kAXErrorInvalidUIElement`).
public struct WindowEntry: Sendable, Hashable, Identifiable {
    /// `CGWindowID` from ScreenCaptureKit. The runtime handle for capture.
    public let windowID: UInt32
    /// `kAXWindowNumber` — the same value as ``windowID`` when AX supplied it, and
    /// the key used to match an AX element back to a ScreenCaptureKit window.
    /// Nil when only ScreenCaptureKit saw this window (e.g. it is on another Space).
    public let windowNumber: Int?
    public let pid: pid_t
    public let title: String
    public let frame: CGRect
    public let flags: WindowFlags
    public let thumbKey: ThumbKey

    public var id: UInt32 { windowID }

    public init(
        windowID: UInt32,
        windowNumber: Int?,
        pid: pid_t,
        title: String,
        frame: CGRect,
        flags: WindowFlags,
        thumbKey: ThumbKey
    ) {
        self.windowID = windowID
        self.windowNumber = windowNumber
        self.pid = pid
        self.title = title
        self.frame = frame
        self.flags = flags
        self.thumbKey = thumbKey
    }
}

extension WindowEntry {
    /// Distinguishes "on another Space" from "we could not see it at all". Only
    /// meaningful when Accessibility described at least one other window of this app,
    /// which is what `appWasDescribed` asserts.
    public func isLikelyOtherSpace(appWasDescribed: Bool) -> Bool {
        appWasDescribed && !flags.contains(.axCorroborated)
    }
}

public struct WindowFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let minimized      = WindowFlags(rawValue: 1 << 0)
    /// Accessibility corroborated this window: it appeared in `kAXWindowsAttribute`,
    /// so we have an authoritative title, its minimized/main state, and an element to
    /// raise it with.
    ///
    /// Absence does **not** mean "on another Space", though that is one cause — AX
    /// only ever reports the current Space. It also covers a denied permission, a
    /// timeout, and a process AX simply will not describe. Callers that want to say
    /// "other Space" must check that AX described *other* windows of the same app
    /// first; see `WindowEntry.isLikelyOtherSpace(appWasDescribed:)`.
    public static let axCorroborated = WindowFlags(rawValue: 1 << 1)
    public static let fullScreen     = WindowFlags(rawValue: 1 << 2)
    /// `kAXMain` — the window the app considers its primary one.
    public static let main           = WindowFlags(rawValue: 1 << 3)
    /// One of several windows the OS presents to the user as tabs of a single window
    /// (Finder, Terminal, Preview…). AX reports each as its own `AXWindow`.
    public static let nativeTab      = WindowFlags(rawValue: 1 << 4)
}
