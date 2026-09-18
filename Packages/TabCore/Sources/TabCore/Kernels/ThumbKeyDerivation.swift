import CryptoKit
import Foundation

/// Derives the persistent cache key for a window's pixels.
///
/// Never include the pid: the OS reuses pids, so a pid-derived key would serve one
/// app's thumbnail for another after a relaunch. Identity must come from something
/// the user would recognise as "the same window".
public enum ThumbKeyDerivation {

    /// Survives restarts and window renames. Use whenever the window has a document
    /// or file URL (`kAXDocumentAttribute`).
    public static func strong(bundleID: String, documentURL: String) -> String {
        digest("\(bundleID)|doc|\(documentURL)")
    }

    /// Title-derived, so a rename silently invalidates it. Evicted before strong keys
    /// and given a short disk TTL.
    public static func weak(bundleID: String, title: String) -> String {
        digest("\(bundleID)|title|\(title)")
    }

    /// Fallback for processes with no bundle id. Session-scoped in practice, since
    /// the pid is not stable across launches.
    public static func weak(pid: pid_t, title: String) -> String {
        digest("pid:\(pid)|title|\(title)")
    }

    /// 128 bits, hex. Enough that a collision across a few thousand cached windows is
    /// not worth defending against, half the bytes of a full SHA-256 on disk.
    static func digest(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
