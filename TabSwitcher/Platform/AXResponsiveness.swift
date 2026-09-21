import ApplicationServices
import Foundation

/// Circuit breaker for unresponsive applications.
///
/// Every accessibility call is a synchronous round-trip serviced on the *target's*
/// main thread. One app stuck in a modal loop will otherwise stall every enumeration
/// pass for the full messaging timeout, repeatedly, forever.
///
/// The load-bearing subtlety: `kAXErrorCannotComplete` means two completely different
/// things depending on how long it took. Returned instantly, the app simply has not
/// finished launching its accessibility tree — normal, and it will work shortly.
/// Returned slowly, the app is genuinely wedged. Only the slow case should trip the
/// breaker; tripping on the fast one would blacklist every app during login.
final class AXResponsiveness: @unchecked Sendable {
    static let shared = AXResponsiveness()

    /// Slower than this and a failure means "hung", not "not ready".
    private let hangThreshold: Duration = .milliseconds(500)
    /// How long a hung process stays skipped before we try it again.
    private let backoff: Duration = .seconds(5)

    private let lock = NSLock()
    private var unresponsive: [pid_t: ContinuousClock.Instant] = [:]
    private let clock = ContinuousClock()

    func isUnresponsive(_ pid: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let markedAt = unresponsive[pid] else { return false }
        if clock.now - markedAt > backoff {
            unresponsive[pid] = nil
            return false
        }
        return true
    }

    /// Feeds one call's outcome back into the breaker.
    func record(pid: pid_t, error: AXError, elapsed: Duration) {
        guard error == .cannotComplete, elapsed >= hangThreshold else {
            if error == .success {
                lock.lock()
                unresponsive[pid] = nil
                lock.unlock()
            }
            return
        }
        lock.lock()
        unresponsive[pid] = clock.now
        lock.unlock()
    }

    func reset() {
        lock.lock()
        unresponsive.removeAll()
        lock.unlock()
    }
}
