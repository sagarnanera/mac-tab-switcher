import CryptoKit
import Foundation

/// Derives the persistent cache key for a window's pixels.
///
/// Never keyed on pid: the OS reuses pids, so a pid-derived key would eventually
/// serve one app's thumbnail for another.
public enum ThumbKeyDerivation {

    public static func key(bundleID: String?, documentURL: String?, title: String, pid: pid_t) -> ThumbKey {
        if let bundleID, let documentURL, !documentURL.isEmpty {
            return .strong(digest("\(bundleID)|doc|\(documentURL)"))
        }
        if let bundleID {
            return .weak(digest("\(bundleID)|title|\(title)"))
        }
        return .weak(digest("pid:\(pid)|title|\(title)"))
    }

    /// 128 bits, hex: half the bytes of a full SHA-256 on disk, and a collision across
    /// a few thousand cached windows is not worth defending against.
    static func digest(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
