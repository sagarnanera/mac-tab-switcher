import CoreGraphics
import Foundation
@testable import SwitcherCore

enum Fixture {
    static func app(_ pid: pid_t, _ name: String) -> AppRef {
        AppRef(pid: pid, bundleID: "test.\(name.lowercased())", name: name)
    }

    static func window(
        _ id: CGWindowID,
        pid: pid_t,
        title: String = "",
        flags: WindowFlags = []
    ) -> WindowEntry {
        WindowEntry(
            id: id,
            pid: pid,
            title: title,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            flags: flags,
            thumbKey: .weak("k\(id)")
        )
    }

    static func group(_ name: String, pid: pid_t, titles: [String]) -> AppGroup {
        AppGroup(
            app: app(pid, name),
            windows: titles.enumerated().map { index, title in
                window(CGWindowID(pid) * 100 + CGWindowID(index), pid: pid, title: title)
            }
        )
    }

    /// Finder (1 window), Code (3), Chrome (2) — the shape the switcher is designed for.
    static var snapshot: WindowSnapshot {
        WindowSnapshot(
            groups: [
                group("Finder", pid: 1, titles: ["Downloads"]),
                group("Code", pid: 2, titles: ["api-server", "tab-switcher", "dotfiles"]),
                group("Chrome", pid: 3, titles: ["GitHub", "Docs"]),
            ],
            capturedAt: .now
        )
    }

    /// A state that has already been summoned, with the standard snapshot loaded.
    static func summoned() -> OverlayState {
        var state = OverlayState()
        _ = state.apply(.snapshotChanged(snapshot))
        _ = state.apply(.summon)
        return state
    }
}

extension OverlayState {
    var selectedAppName: String? { selectedApp?.app.name }
    var selectedTitle: String? { selectedWindow?.title }
}
