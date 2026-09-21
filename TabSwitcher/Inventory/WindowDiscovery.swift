import AppKit
import Foundation
import SwitcherCore

struct DiscoveryResult: Sendable {
    let windows: [WindowEntry]
    let apps: [AppRef]
    /// Live accessibility elements for raising, keyed by window id. Not part of
    /// `WindowEntry`, which must stay pure and `Sendable`.
    let elements: [CGWindowID: AXElement]
    let timings: [String: Duration]
}

/// Merges the Window Server list, accessibility, Spaces and `NSWorkspace` into the
/// window model the switcher renders.
///
/// | Source | Authoritative for |
/// |---|---|
/// | Window Server | existence, id, geometry, layer, alpha |
/// | Accessibility | titles, minimized/main, document URL, the element to raise |
/// | Spaces (private) | which Space a window is on |
/// | NSWorkspace | app identity and icon |
enum WindowDiscovery {

    static func run() async -> DiscoveryResult {
        let clock = ContinuousClock()
        var timings: [String: Duration] = [:]

        var mark = clock.now
        let apps = runningApps()
        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        timings["apps"] = clock.now - mark

        mark = clock.now
        let candidates = CGWindowList.candidates().filter { appsByPID[$0.pid] != nil }
        timings["windowserver"] = clock.now - mark

        mark = clock.now
        let visibleSpaces = PrivateAPI.visibleSpaceIDs()
        let spacesByWindow = spaceMembership(for: candidates.map(\.id))
        timings["spaces"] = clock.now - mark

        // Only pay for brute-force probing where the Window Server proves accessibility
        // is hiding something: a window that belongs to no currently visible Space.
        let offSpacePIDs = Set(
            candidates
                .filter { candidate in
                    guard let spaces = spacesByWindow[candidate.id], !spaces.isEmpty else { return false }
                    return spaces.isDisjoint(with: visibleSpaces)
                }
                .map(\.pid)
        )

        mark = clock.now
        let axByPID = await AXWindowReader.read(pids: apps.map(\.pid), needingBruteForce: offSpacePIDs)
        timings["accessibility"] = clock.now - mark

        let merged = merge(
            candidates: candidates,
            axByPID: axByPID,
            appsByPID: appsByPID,
            spacesByWindow: spacesByWindow,
            visibleSpaces: visibleSpaces
        )
        timings["total"] = timings.values.reduce(.zero, +)
        return DiscoveryResult(
            windows: merged.windows, apps: apps, elements: merged.elements, timings: timings
        )
    }

    // MARK: - Merge

    private static func merge(
        candidates: [CGWindowCandidate],
        axByPID: [pid_t: [AXWindow]],
        appsByPID: [pid_t: AppRef],
        spacesByWindow: [CGWindowID: Set<CGSSpaceID>],
        visibleSpaces: Set<CGSSpaceID>
    ) -> (windows: [WindowEntry], elements: [CGWindowID: AXElement]) {

        var axByWindowID: [CGWindowID: AXWindow] = [:]
        var unmatchedAX: [pid_t: [AXWindow]] = [:]
        for (pid, windows) in axByPID {
            for window in windows {
                if let id = window.windowID { axByWindowID[id] = window }
                else { unmatchedAX[pid, default: []].append(window) }
            }
        }

        // If nothing at all is titled while plenty of windows exist, the Window Server
        // is withholding titles rather than every window genuinely being unnamed.
        let titlesAvailable = candidates.contains { !$0.title.isEmpty }

        // Resolve every title first. Fallback names are invented in a second pass, so
        // a surface processed early cannot claim a name that a real title needs — that
        // ordering dependence produced two tiles both labelled "Claude".
        var resolvedTitles: [CGWindowID: String] = [:]
        for candidate in candidates {
            let ax = axByWindowID[candidate.id]
                ?? unmatchedAX[candidate.pid]?.first { window in
                    window.title == candidate.title && window.frame.isCloseTo(candidate.frame)
                }
            resolvedTitles[candidate.id] = (ax?.title).flatMap { $0.isEmpty ? nil : $0 }
                ?? candidate.title
        }
        var usedTitlesByPID: [pid_t: Set<String>] = [:]
        for candidate in candidates {
            guard let title = resolvedTitles[candidate.id], !title.isEmpty else { continue }
            usedTitlesByPID[candidate.pid, default: []].insert(title)
        }

        let tabbed = nativeTabWindowIDs(axByPID: axByPID)
        var entries: [WindowEntry] = []
        var elements: [CGWindowID: AXElement] = [:]

        for candidate in candidates {
            // `_AXUIElementGetWindow` is private. When it is unavailable or fails, fall
            // back to matching within the same process on title and geometry.
            let ax = axByWindowID[candidate.id]
                ?? unmatchedAX[candidate.pid]?.first { window in
                    window.title == candidate.title && window.frame.isCloseTo(candidate.frame)
                }

            let resolved = resolvedTitles[candidate.id] ?? ""
            let evidence: WindowFilter.Evidence =
                ax != nil ? .accessibility : (titlesAvailable ? .titlesAvailable : .geometryOnly)
            guard WindowFilter.isRenderable(title: resolved, evidence: evidence) else { continue }

            // A tile still has to say *something*. Falling back to the app name,
            // numbered when there are several, keeps the switcher usable with no
            // permissions at all.
            var title = resolved
            if title.isEmpty {
                let appName = appsByPID[candidate.pid]?.name ?? "Window"
                var candidateTitle = appName
                var index = 1
                while usedTitlesByPID[candidate.pid, default: []].contains(candidateTitle) {
                    index += 1
                    candidateTitle = "\(appName) \(index)"
                }
                title = candidateTitle
            }
            usedTitlesByPID[candidate.pid, default: []].insert(title)

            var flags: WindowFlags = []
            if ax?.isMinimized == true { flags.insert(.minimized) }
            if ax?.isMain == true { flags.insert(.main) }
            if tabbed.contains(candidate.id) { flags.insert(.nativeTab) }
            if let spaces = spacesByWindow[candidate.id], !spaces.isEmpty,
               spaces.isDisjoint(with: visibleSpaces) {
                flags.insert(.otherSpace)
            }

            entries.append(
                WindowEntry(
                    id: candidate.id,
                    pid: candidate.pid,
                    title: title,
                    frame: candidate.frame,
                    flags: flags,
                    thumbKey: ThumbKeyDerivation.key(
                        bundleID: appsByPID[candidate.pid]?.bundleID,
                        documentURL: ax?.documentURL,
                        title: title,
                        pid: candidate.pid
                    )
                )
            )
            if let element = ax?.element { elements[candidate.id] = element }
        }
        return (entries, elements)
    }

    /// Native macOS tabs have a distinctive signature: several accessibility windows of
    /// one process occupying the identical frame, because only the selected tab is
    /// drawn there. No public API reports tab membership.
    private static func nativeTabWindowIDs(axByPID: [pid_t: [AXWindow]]) -> Set<CGWindowID> {
        var tabbed: Set<CGWindowID> = []
        for (_, windows) in axByPID where windows.count > 1 {
            var byFrame: [String: [AXWindow]] = [:]
            for window in windows {
                let key = "\(Int(window.frame.origin.x)),\(Int(window.frame.origin.y))"
                    + ",\(Int(window.frame.width)),\(Int(window.frame.height))"
                byFrame[key, default: []].append(window)
            }
            for (_, sharing) in byFrame where sharing.count > 1 {
                tabbed.formUnion(sharing.compactMap(\.windowID))
            }
        }
        return tabbed
    }

    private static func spaceMembership(for ids: [CGWindowID]) -> [CGWindowID: Set<CGSSpaceID>] {
        guard PrivateAPI.has(.spacesForWindows) else { return [:] }
        // Queried one window at a time: the API returns a flat union for a batch, with
        // no way to attribute a Space back to a window.
        var membership: [CGWindowID: Set<CGSSpaceID>] = [:]
        for id in ids {
            membership[id] = Set(PrivateAPI.spaces(for: [id]))
        }
        return membership
    }

    /// `NSRunningApplication` is documented thread-safe and is `Sendable`, so this runs
    /// off the main actor deliberately: the first read of an app's bundle URL and icon
    /// costs tens of milliseconds, which would be a visible stall on the main thread.
    private static func runningApps() -> [AppRef] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map {
                AppRef(
                    pid: $0.processIdentifier,
                    bundleID: $0.bundleIdentifier,
                    name: $0.localizedName ?? $0.bundleIdentifier ?? "pid \($0.processIdentifier)"
                )
            }
    }
}

extension CGRect {
    /// Accessibility and the Window Server disagree by sub-pixel amounts on the same
    /// window.
    func isCloseTo(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
