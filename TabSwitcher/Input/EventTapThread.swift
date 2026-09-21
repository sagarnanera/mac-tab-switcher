import CoreGraphics
import Foundation

/// A dedicated thread whose run loop hosts the keyboard event tap.
///
/// The tap must not live on the main run loop. macOS disables a tap whose owner fails
/// to service events promptly (`tapDisabledByTimeout`), and the main thread is exactly
/// where a slow frame or a synchronous system call will happen. A tap that dies
/// silently means the switcher simply stops responding to the modifier release, which
/// is indistinguishable from a bug in the state machine.
final class EventTapThread: @unchecked Sendable {
    static let shared = EventTapThread()

    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    private init() {
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            // A run loop with no sources exits immediately; this keeps it alive.
            var context = CFRunLoopSourceContext()
            let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAlive, .commonModes)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "dev.nanera.tabswitcher.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    func add(_ source: CFRunLoopSource) {
        guard let runLoop else { return }
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CFRunLoopWakeUp(runLoop)
    }
}
