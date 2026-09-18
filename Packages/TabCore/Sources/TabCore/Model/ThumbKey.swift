import Foundation

/// Persistent identity for a window's cached pixels.
///
/// Split by strength because the two kinds have different lifetimes on disk:
/// a document-derived key survives restarts and window renames, a title-derived
/// key does not and must be evicted first.
public enum ThumbKey: Sendable, Hashable {
    /// Derived from a stable document or file URL (`kAXDocumentAttribute`).
    /// Persisted indefinitely.
    case strong(String)
    /// Derived from the window title. Memory tier plus a short disk TTL — a
    /// renamed window silently invalidates it, so it must never crowd out
    /// strong keys.
    case weak(String)

    public var hex: String {
        switch self {
        case .strong(let h), .weak(let h): return h
        }
    }

    public var isStrong: Bool {
        if case .strong = self { return true }
        return false
    }
}
