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
    /// Apps Accessibility described this pass. Needed to interpret a missing
    /// `.axCorroborated` flag — see `WindowEntry.isLikelyOtherSpace`.
    private(set) var describedPIDs: Set<pid_t> = []

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
        describedPIDs = Set(axByPID.filter { !$0.value.isEmpty }.keys)
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

    /// Diagnostic: every ScreenCaptureKit window grouped by app, with the attributes
    /// the filter keys on, plus whether Accessibility corroborated it.
    func dumpRaw() async {
        let apps = Self.runningApps()
        let byPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        guard let shareable = try? await content.refresh() else {
            print("screencapturekit unavailable")
            return
        }
        let axByPID = await AXWindowReader.readWindows(pids: apps.map(\.pid))
        var axIDs: Set<CGWindowID> = []
        for (_, windows) in axByPID { axIDs.formUnion(windows.compactMap(\.windowID)) }

        print("total screencapturekit windows: \(shareable.count)")
        print("layer histogram: \(Dictionary(grouping: shareable, by: \.layer).mapValues(\.count).sorted { $0.key < $1.key })")
        print("")
        for (pid, windows) in Dictionary(grouping: shareable, by: \.pid).sorted(by: { $0.key < $1.key }) {
            guard let app = byPID[pid] else { continue }
            print("\(app.localizedName) [pid \(pid)] — \(windows.count) surfaces, ax saw \(axByPID[pid]?.count ?? 0)")
            for w in windows.sorted(by: { $0.windowID < $1.windowID }) {
                let size = "\(Int(w.frame.width))x\(Int(w.frame.height))"
                let pos = "@\(Int(w.frame.origin.x)),\(Int(w.frame.origin.y))"
                let ax = axIDs.contains(w.windowID) ? "ax" : "--"
                let screen = w.isOnScreen ? "on" : "off"
                print("    id \(w.windowID)  layer \(w.layer)  \(ax)  \(screen)  \(size) \(pos)  \"\(w.title)\"")
            }
        }
    }

    // MARK: - Merge

    private func merge(
        shareable: [ShareableWindow],
        axByPID: [pid_t: [AXWindow]],
        apps: [AppRef]
    ) -> [WindowEntry] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let knownPIDs = Set(apps.map(\.pid))

        // ScreenCaptureKit reports ~200 surfaces on an ordinary desktop, of which a
        // handful are windows a person would switch to. Measured on macOS 27, every
        // app contributes the same junk: four 1512x33 strips at the origin (menu bar
        // backing) and a 500x500 or 64x64 helper at y=482. Layer and size cull most
        // of it; the decisive rule is below.
        //
        // `isOnScreen` is deliberately NOT used: it reads false even for plainly
        // visible frontmost windows.
        let candidates = shareable.filter { window in
            window.pid != ownPID
                && knownPIDs.contains(window.pid)
                && window.layer == 0                       // menus, docks, overlays, tooltips all sit higher or lower
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

        // Which apps AX described at all. Lets us tell "this window is on another
        // Space" apart from "AX told us nothing about this app", which look identical
        // from a single window's point of view.
        let describedPIDs = Set(axByPID.filter { !$0.value.isEmpty }.keys)

        for window in candidates {
            // `_AXUIElementGetWindow` is private; if it ever stops resolving, fall
            // back to matching on geometry and title within the same process.
            let ax = axByWindowID[window.windowID]
                ?? unmatchedAX[window.pid]?.first { $0.title == window.title && $0.frame.equalish(window.frame) }

            // The decisive filter: a window with no title from either source is not
            // something a person can pick out of a switcher, and in practice is always
            // one of the helper surfaces above. Keep it only if AX vouches for it,
            // since AX sometimes supplies a title ScreenCaptureKit lacks.
            let resolvedTitle = (ax?.title).flatMap { $0.isEmpty ? nil : $0 } ?? window.title
            guard !resolvedTitle.isEmpty || ax != nil else { continue }

            var flags: WindowFlags = []
            if let ax {
                flags.insert(.axCorroborated)
                if ax.isMinimized { flags.insert(.minimized) }
                if ax.isMain { flags.insert(.main) }
            }
            if tabbed.contains(window.windowID) { flags.insert(.nativeTab) }

            refs.append(
                WindowEntry(
                    windowID: window.windowID,
                    windowNumber: ax?.windowID.map(Int.init),
                    pid: window.pid,
                    title: resolvedTitle.isEmpty ? "(untitled)" : resolvedTitle,
                    frame: window.frame,
                    flags: flags,
                    thumbKey: .weak(ThumbKeyDerivation.weak(pid: window.pid, title: resolvedTitle))
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
