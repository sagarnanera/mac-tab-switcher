import Foundation

/// Whether the app's own code signature still validates.
///
/// This exists because of how this app is signed and what it needs. TCC keys its grants
/// to the code signature, so a bundle whose signature has broken keeps its Accessibility
/// and Screen Recording grants on paper while being refused them in practice — and a
/// revoked permission and a denied one are indistinguishable from inside the app. The
/// user sees a switcher that has silently stopped finding windows.
///
/// Sparkle has a known failure mode that produces exactly this: an in-place update can
/// leave the outer bundle's sealed-resource manifest stale relative to what is on disk,
/// so the signature no longer verifies (sparkle-project, imputnet/helium-macos#339).
/// Since we ship self-signed rather than notarized, there is no Gatekeeper check on
/// launch that would catch it first.
///
/// Checked rather than assumed, and reported rather than repaired: re-signing in place is
/// not something an app should do to itself.
enum BundleIntegrity {

    enum Result: Equatable {
        case valid
        /// `codesign` rejected the bundle. The string is its own message, which names the
        /// offending resource and is the only useful thing to put in a bug report.
        case broken(String)
        /// The check could not run. Not treated as failure — an unavailable tool says
        /// nothing about the bundle.
        case unknown
    }

    static func verify(bundlePath: String = Bundle.main.bundlePath) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", bundlePath]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return .unknown
        }
        // Read before waiting: codesign's output on a badly broken bundle can fill the
        // pipe buffer, and a full pipe with nobody reading it deadlocks the wait.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return .valid }
        let message = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .broken(message.isEmpty ? "codesign exited \(process.terminationStatus)" : message)
    }
}
