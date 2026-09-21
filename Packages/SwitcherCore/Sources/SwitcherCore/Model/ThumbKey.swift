import Foundation

/// Persistent identity for a window's cached pixels.
///
/// Split by strength because the two kinds have different lifetimes on disk: a
/// document-derived key survives restarts and window renames, a title-derived key
/// survives neither and must be evicted first.
public enum ThumbKey: Sendable, Hashable {
    case strong(String)
    case weak(String)

    public var hex: String {
        switch self {
        case .strong(let value), .weak(let value): value
        }
    }

    public var isStrong: Bool {
        if case .strong = self { return true }
        return false
    }
}
