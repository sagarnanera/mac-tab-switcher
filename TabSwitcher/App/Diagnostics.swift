import Foundation
import os

/// Logging and the self-report that says which private symbols resolved.
///
/// The availability report matters: every private capability has a public fallback, so
/// a user reporting "no previews for minimized windows" is answered by this list
/// rather than by guesswork.
enum Diagnostics {
    private static let logger = Logger(subsystem: "dev.nanera.tabswitcher", category: "app")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func capabilityReport() -> String {
        PrivateAPI.availability
            .sorted { $0.key < $1.key }
            .map { "\($0.value ? "ok    " : "MISSING") \($0.key)" }
            .joined(separator: "\n")
    }
}
