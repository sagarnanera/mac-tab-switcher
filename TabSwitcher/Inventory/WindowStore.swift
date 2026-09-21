import AppKit
import Foundation
import SwitcherCore

/// Keeps the window list warm so the hotkey never has to look anything up.
///
/// This is the single most important performance decision in the app. AltTab spends
/// 80-90ms on a summon because it *gathers* the window list while the user is pressing
/// the key. Here, discovery runs on app launch and on system events, and pressing the
/// hotkey only reads memory — so the framework rendering the overlay stops being the
/// bottleneck and the budget is spent on drawing rather than on cross-process calls.
actor WindowStore {
    private var snapshot: WindowSnapshot = .empty
    private var elements: [CGWindowID: AXElement] = [:]
    private var appMRU: [pid_t] = []
    private var windowMRU: [CGWindowID] = []
    private var options: AppGrouping.Options = .default
    private var refreshTask: Task<Void, Never>?
    private var lastTimings: [String: Duration] = [:]

    /// Called on the main actor whenever a fresh snapshot lands.
    private var onUpdate: (@Sendable @MainActor (WindowSnapshot) -> Void)?

    func setUpdateHandler(_ handler: @escaping @Sendable @MainActor (WindowSnapshot) -> Void) {
        onUpdate = handler
    }

    func setGroupingOptions(_ options: AppGrouping.Options) {
        self.options = options
    }

    var current: WindowSnapshot { snapshot }
    var timings: [String: Duration] { lastTimings }

    func element(for windowID: CGWindowID) -> AXElement? { elements[windowID] }

    /// Records a switch so the next summon lands on the right place. Called after a
    /// successful activation and on `NSWorkspace` activation notices, so the ordering
    /// reflects switches the user made outside the app too.
    func noteActivation(pid: pid_t, windowID: CGWindowID?) {
        appMRU.removeAll { $0 == pid }
        appMRU.insert(pid, at: 0)
        if let windowID {
            windowMRU.removeAll { $0 == windowID }
            windowMRU.insert(windowID, at: 0)
        }
        regroup()
    }

    /// Coalesces bursts: window notifications arrive in clusters (opening a window
    /// fires created, moved, resized and titleChanged within a few milliseconds), and
    /// running a full pass for each would be pure waste.
    func requestRefresh(debounce: Duration = .milliseconds(150)) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    func refresh() async {
        let result = await WindowDiscovery.run()
        guard !Task.isCancelled else { return }

        elements = result.elements
        lastTimings = result.timings
        rebuild(windows: result.windows, apps: result.apps)
    }

    // MARK: - Private

    private var lastWindows: [WindowEntry] = []
    private var lastApps: [AppRef] = []

    private func rebuild(windows: [WindowEntry], apps: [AppRef]) {
        lastWindows = windows
        lastApps = apps
        regroup()
    }

    private func regroup() {
        let groups = AppGrouping.group(
            windows: lastWindows,
            apps: lastApps,
            appMRU: appMRU,
            windowMRU: windowMRU,
            options: options
        )
        snapshot = WindowSnapshot(groups: groups, capturedAt: .now)
        let published = snapshot
        if let onUpdate {
            Task { @MainActor in onUpdate(published) }
        }
    }
}
