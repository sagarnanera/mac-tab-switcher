import CoreGraphics
import Testing
@testable import TabCore

private func app(_ pid: pid_t, _ name: String) -> AppRef {
    AppRef(pid: pid, bundleID: "test.\(name.lowercased())", localizedName: name)
}

private func win(
    _ id: UInt32,
    pid: pid_t,
    title: String = "",
    flags: WindowFlags = []
) -> WindowEntry {
    WindowEntry(
        windowID: id,
        windowNumber: Int(id),
        pid: pid,
        title: title,
        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
        flags: flags,
        thumbKey: .weak("k\(id)")
    )
}

@Suite("AppGrouping")
struct AppGroupingTests {

    @Test("groups windows under their owning app")
    func groupsByApp() {
        let apps = [app(1, "Code"), app(2, "Finder")]
        let windows = [win(10, pid: 1), win(11, pid: 1), win(20, pid: 2)]

        let groups = AppGrouping.group(windows: windows, apps: apps)

        #expect(groups.count == 2)
        #expect(groups.first { $0.app.pid == 1 }?.windows.count == 2)
        #expect(groups.first { $0.app.pid == 2 }?.windows.count == 1)
    }

    @Test("two windows of one app stay in one group — the core promise")
    func twoWindowsOneGroup() {
        let groups = AppGrouping.group(
            windows: [win(10, pid: 1, title: "api-server"), win(11, pid: 1, title: "tab-switcher")],
            apps: [app(1, "Code")]
        )

        #expect(groups.count == 1)
        #expect(groups[0].expandable)
        #expect(groups[0].windows.map(\.title) == ["api-server", "tab-switcher"])
    }

    @Test("apps order by MRU, unknown pids trail in apps order")
    func appMRUOrdering() {
        let apps = [app(1, "Code"), app(2, "Finder"), app(3, "Chrome")]
        let windows = [win(10, pid: 1), win(20, pid: 2), win(30, pid: 3)]

        let groups = AppGrouping.group(windows: windows, apps: apps, appMRU: [3, 1])

        #expect(groups.map(\.app.pid) == [3, 1, 2])
    }

    @Test("windows order by MRU, then main, then title")
    func windowOrdering() {
        let windows = [
            win(10, pid: 1, title: "zebra"),
            win(11, pid: 1, title: "alpha"),
            win(12, pid: 1, title: "beta", flags: .main),
        ]

        let byTitle = AppGrouping.group(windows: windows, apps: [app(1, "Code")])
        #expect(byTitle[0].windows.map(\.title) == ["beta", "alpha", "zebra"])

        let byMRU = AppGrouping.group(windows: windows, apps: [app(1, "Code")], windowMRU: [10])
        #expect(byMRU[0].windows.map(\.title) == ["zebra", "beta", "alpha"])
    }

    @Test("ordering is total, so repeated passes are identical")
    func orderingIsStable() {
        let windows = [
            win(12, pid: 1, title: "same"),
            win(10, pid: 1, title: "same"),
            win(11, pid: 1, title: "same"),
        ]
        let first = AppGrouping.group(windows: windows, apps: [app(1, "Code")])
        let second = AppGrouping.group(windows: windows.reversed(), apps: [app(1, "Code")])

        #expect(first[0].windows.map(\.windowID) == [10, 11, 12])
        #expect(first[0].windows.map(\.windowID) == second[0].windows.map(\.windowID))
    }

    @Test("windows of unknown pids are dropped")
    func dropsUnknownPIDs() {
        let groups = AppGrouping.group(
            windows: [win(10, pid: 1), win(99, pid: 42)],
            apps: [app(1, "Code")]
        )

        #expect(groups.count == 1)
        #expect(groups[0].windows.map(\.windowID) == [10])
    }

    @Test("an app with no surviving windows produces no group")
    func noEmptyGroups() {
        let groups = AppGrouping.group(
            windows: [win(10, pid: 1, flags: .minimized)],
            apps: [app(1, "Code"), app(2, "Finder")],
            options: .init(includeMinimized: false)
        )

        #expect(groups.isEmpty)
    }

    @Test("groupNativeTabs false collapses a tab set to its main window")
    func nativeTabFolding() {
        let tabs = [
            win(10, pid: 1, title: "Downloads", flags: [.nativeTab, .main]),
            win(11, pid: 1, title: "Projects", flags: .nativeTab),
            win(12, pid: 1, title: "Desktop", flags: .nativeTab),
        ]

        let expanded = AppGrouping.group(windows: tabs, apps: [app(1, "Finder")])
        #expect(expanded[0].windows.count == 3)

        let folded = AppGrouping.group(
            windows: tabs,
            apps: [app(1, "Finder")],
            options: .init(groupNativeTabs: false)
        )
        #expect(folded[0].windows.map(\.title) == ["Downloads"])
    }

    @Test("single-window apps are not expandable")
    func expandability() {
        let groups = AppGrouping.group(windows: [win(10, pid: 1)], apps: [app(1, "Slack")])
        #expect(!groups[0].expandable)
    }

    @Test("empty input yields no groups")
    func emptyInput() {
        #expect(AppGrouping.group(windows: [], apps: [app(1, "Code")]).isEmpty)
        #expect(AppGrouping.group(windows: [win(10, pid: 1)], apps: []).isEmpty)
    }
}
