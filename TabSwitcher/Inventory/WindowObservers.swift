import AppKit
import ApplicationServices
import Foundation

/// Watches the system for anything that changes the window list, so the store stays
/// warm without polling.
///
/// Polling would either be too slow (a stale list at the moment of a switch) or too
/// expensive (a full cross-process pass on a timer, forever). Events give both.
@MainActor
final class WindowObservers {
    private let store: WindowStore
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []

    /// The notifications that actually change what the switcher should draw.
    private static let watched: [String] = [
        kAXWindowCreatedNotification as String,
        kAXUIElementDestroyedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXTitleChangedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String,
    ]

    init(store: WindowStore) {
        self.store = store
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let interesting: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
        ]
        for name in interesting {
            tokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self else { return }
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    MainActor.assumeIsolated {
                        self.handleWorkspace(name: name, app: app)
                    }
                }
            )
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attach(to: app.processIdentifier)
        }
    }

    private func handleWorkspace(name: NSNotification.Name, app: NSRunningApplication?) {
        if name == NSWorkspace.didLaunchApplicationNotification, let app {
            attach(to: app.processIdentifier)
        }
        if name == NSWorkspace.didTerminateApplicationNotification, let app {
            detach(from: app.processIdentifier)
        }
        if name == NSWorkspace.didActivateApplicationNotification, let app {
            // Records switches the user made outside our overlay, so MRU order reflects
            // reality rather than only what we did ourselves.
            let pid = app.processIdentifier
            Task { await store.noteActivation(pid: pid, windowID: nil) }
        }
        Task { await store.requestRefresh() }
    }

    /// One observer per *process*, never per window: per-window observer sources leak,
    /// and a busy app can create and destroy windows faster than they can be managed.
    private func attach(to pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let store = Unmanaged<StoreBox>.fromOpaque(context).takeUnretainedValue().store
            Task { await store.requestRefresh() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

        let box = StoreBox(store: store)
        let context = Unmanaged.passRetained(box).toOpaque()
        let element = AXUIElementCreateApplication(pid)
        for notification in Self.watched {
            AXObserverAddNotification(observer, element, notification as CFString, context)
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
        )
        observers[pid] = observer
    }

    private func detach(from pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
        )
    }
}

/// Carries the store through the C callback's opaque context pointer, which cannot
/// capture Swift values.
private final class StoreBox: @unchecked Sendable {
    let store: WindowStore
    init(store: WindowStore) { self.store = store }
}
