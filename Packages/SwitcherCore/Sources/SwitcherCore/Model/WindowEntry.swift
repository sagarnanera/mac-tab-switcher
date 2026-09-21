import CoreGraphics
import Foundation

/// One switchable window.
///
/// Named `WindowEntry` rather than `WindowRef` because Carbon exports a global
/// `WindowRef` that AppKit re-exports transitively; the collision is unresolvable
/// at every use site without qualifying.
///
/// Holds no `AXUIElement`. This type must stay `Sendable` and constructible in tests,
/// so the live element lives in a side table keyed by ``id`` in the app target.
public struct WindowEntry: Sendable, Hashable, Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let title: String
    public let frame: CGRect
    public let flags: WindowFlags
    public let thumbKey: ThumbKey

    public init(
        id: CGWindowID,
        pid: pid_t,
        title: String,
        frame: CGRect,
        flags: WindowFlags,
        thumbKey: ThumbKey
    ) {
        self.id = id
        self.pid = pid
        self.title = title
        self.frame = frame
        self.flags = flags
        self.thumbKey = thumbKey
    }
}

public struct WindowFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let minimized  = WindowFlags(rawValue: 1 << 0)
    public static let hidden     = WindowFlags(rawValue: 1 << 1)
    public static let fullScreen = WindowFlags(rawValue: 1 << 2)
    /// The window the owning app considers primary.
    public static let main       = WindowFlags(rawValue: 1 << 3)
    /// One of several windows macOS presents as tabs of a single window. AX reports
    /// each as its own `AXWindow`; there is no public API for tab membership.
    public static let nativeTab  = WindowFlags(rawValue: 1 << 4)
    /// Lives on a Space other than any currently visible one.
    public static let otherSpace = WindowFlags(rawValue: 1 << 5)

    /// Windows whose pixels the compositor may not have. Callers use this to decide
    /// whether a missing thumbnail is a bug or expected.
    public var mayLackPixels: Bool { contains(.minimized) || contains(.hidden) }
}
