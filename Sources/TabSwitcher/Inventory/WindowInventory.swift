import AppKit
import Foundation
import TabCore

struct InventoryResult: Sendable {
    let groups: [AppGroup]
    let diagnostics: [String]
}

/// Merges the three sources of truth into `[AppGroup]`.
///
/// | Source | Authoritative for |
/// |---|---|
/// | ScreenCaptureKit | window *existence*, `CGWindowID`, geometry — including windows on other Spaces and fully occluded ones |
/// | Accessibility | titles, minimized/main state, native tabs, and the element needed to raise |
/// | NSWorkspace | app identity: bundle id, localized name |
///
/// Neither of the first two is sufficient alone: AX reports only the current Space,
/// and ScreenCaptureKit cannot see native tabs or raise anything.
actor WindowInventory {
    private let content = ShareableContentCache()
    /// windowID → AX element, rebuilt each pass. The raise path re-resolves through
    /// here rather than holding elements in `WindowEntry`, which must stay pure.
    private(set) var elements: [UInt32: AXElementBox] = [:]

    private var appMRU: [pid_t] = []
    private var windowMRU: [UInt32] = []

    func noteActivation(app pid: pid_t, window windowID: UInt32?) {
        appMRU.removeAll { $0 == pid }
        appMRU.insert(pid, at: 0)
        if let windowID {
            windowMRU.removeAll { $0 == windowID }
            windowMRU.insert(windowID, at: 0)
        }
    }

    func element(for windowID: UInt32) -> AXElementBox? { elements[windowID] }

    func enumerate(options: AppGrouping.Options = .default) async -> InventoryResult {
        var diagnostics: [String] = []
        let clock = ContinuousClock()

        let start = clock.now
        let apps = Self.runningApps()
        diagnostics.append("apps: \(apps.count) in \(ms(clock.now - start))")

        let scStart = clock.now
        var shareable: [ShareableWindow] = []
        do {
            shareable = try await content.refresh()
            diagnostics.append("screencapturekit: \(shareable.count) windows in \(ms(clock.now - scStart))")
        } catch {
            diagnostics.append("screencapturekit: FAILED — \(error)")
        }

        let axStart = clock.now
        let axByPID = await AXWindowReader.readWindows(pids: apps.map(\.pid))
        let axCount = axByPID.values.reduce(0) { $0 + $1.count }
        diagnostics.append("accessibility: \(axCount) windows across \(axByPID.count) apps in \(ms(clock.now - axStart))")

        let windows = merge(shareable: shareable, axByPID: axByPID, apps: apps)
        elements = Dictionary(
            windows.compactMap { ref in axElement(for: ref, in: axByPID).map { (ref.windowID, $0) } },
            uniquingKeysWith: { first, _ in first }
        )

        let groups = AppGrouping.group(
            windows: windows,
            apps: apps,
            appMRU: appMRU,
            windowMRU: windowMRU,
            options: options
        )
        diagnostics.append("total: \(groups.count) apps, \(windows.count) windows in \(ms(clock.now - start))")
        return InventoryResult(groups: groups, diagnostics: diagnostics)
    }

    // MARK: - Merge

    private func merge(
        shareable: [ShareableWindow],
        axByPID: [pid_t: [AXWindow]],
        apps: [AppRef]
    ) -> [WindowEntry] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let knownPIDs = Set(apps.map(\.pid))

        let candidates = shareable.filter { window in
            window.pid != ownPID
                && knownPIDs.contains(window.pid)
                && window.layer == 0                       // 0 = normal app windows; menus, docks, overlays are higher
                && window.frame.width >= 64 && window.frame.height >= 64
        }

        var axByWindowID: [CGWindowID: AXWindow] = [:]
        var unmatchedAX: [pid_t: [AXWindow]] = [:]
        for (pid, axWindows) in axByPID {
            for ax in axWindows {
                if let id = ax.windowID {
                    axByWindowID[id] = ax
                } else {
                    unmatchedAX[pid, default: []].append(ax)
                }
            }
        }

        let tabbed = nativeTabWindowIDs(axByPID: axByPID)
        var refs: [WindowEntry] = []

        for window in candidates {
            // `_AXUIElementGetWindow` is private; if it ever stops resolving, fall
            // back to matching on geometry and title within the same process.
            let ax = axByWindowID[window.windowID]
                ?? unmatchedAX[window.pid]?.first { $0.title == window.title && $0.frame.equalish(window.frame) }

            var flags: WindowFlags = []
            if let ax {
                flags.insert(.onCurrentSpace)
                if ax.isMinimized { flags.insert(.minimized) }
                if ax.isMain { flags.insert(.main) }
            }
            if tabbed.contains(window.windowID) { flags.insert(.nativeTab) }

            let title = (ax?.title).flatMap { $0.isEmpty ? nil : $0 } ?? window.title
            refs.append(
                WindowEntry(
                    windowID: window.windowID,
                    windowNumber: ax?.windowID.map(Int.init),
                    pid: window.pid,
                    title: title.isEmpty ? "(untitled)" : title,
                    frame: window.frame,
                    flags: flags,
                    thumbKey: .weak(ThumbKeyDerivation.weak(pid: window.pid, title: title))
                )
            )
        }
        return refs
    }

    /// Native macOS tabs have a distinctive signature: several `AXWindow`s of one
    /// process occupying the exact same frame, because only the selected tab is
    /// actually drawn there. No public API reports tab membership.
    private func nativeTabWindowIDs(axByPID: [pid_t: [AXWindow]]) -> Set<CGWindowID> {
        var tabbed: Set<CGWindowID> = []
        for (_, axWindows) in axByPID where axWindows.count > 1 {
            var byFrame: [String: [AXWindow]] = [:]
            for ax in axWindows {
                let key = "\(Int(ax.frame.origin.x)),\(Int(ax.frame.origin.y)),\(Int(ax.frame.width)),\(Int(ax.frame.height))"
                byFrame[key, default: []].append(ax)
            }
            for (_, sharing) in byFrame where sharing.count > 1 {
                tabbed.formUnion(sharing.compactMap(\.windowID))
            }
        }
        return tabbed
    }

    private func axElement(for ref: WindowEntry, in axByPID: [pid_t: [AXWindow]]) -> AXElementBox? {
        guard let axWindows = axByPID[ref.pid] else { return nil }
        if let exact = axWindows.first(where: { $0.windowID == ref.windowID }) { return exact.element }
        return axWindows.first { $0.title == ref.title && $0.frame.equalish(ref.frame) }?.element
    }

    // MARK: - Apps

    /// `NSRunningApplication` is `NS_SWIFT_SENDABLE` and documented thread-safe, so
    /// this is deliberately *not* hopped to the main actor: the first read of
    /// `bundleURL`/`icon` for a process costs ~56ms, which would be a visible stall.
    nonisolated private static func runningApps() -> [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map {
                AppRef(
                    pid: $0.processIdentifier,
                    bundleID: $0.bundleIdentifier,
                    localizedName: $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)"
                )
            }
    }

    private func ms(_ duration: Duration) -> String {
        String(format: "%.1fms", Double(duration.components.attoseconds) / 1e15
            + Double(duration.components.seconds) * 1000)
    }
}

extension CGRect {
    /// AX and ScreenCaptureKit disagree by sub-pixel amounts on the same window.
    func equalish(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
