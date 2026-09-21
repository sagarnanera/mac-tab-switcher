import CoreGraphics
import Testing
@testable import SwitcherCore

@Suite("AppGrouping")
struct AppGroupingTests {

    @Test("two windows of one app stay in one group — the core promise")
    func twoWindowsOneGroup() {
        let groups = AppGrouping.group(
            windows: [
                Fixture.window(10, pid: 1, title: "api-server"),
                Fixture.window(11, pid: 1, title: "tab-switcher"),
            ],
            apps: [Fixture.app(1, "Code")]
        )
        #expect(groups.count == 1)
        #expect(groups[0].isExpandable)
    }

    @Test("apps order by MRU; unknown pids trail in input order")
    func appOrdering() {
        let groups = AppGrouping.group(
            windows: [Fixture.window(10, pid: 1), Fixture.window(20, pid: 2), Fixture.window(30, pid: 3)],
            apps: [Fixture.app(1, "Code"), Fixture.app(2, "Finder"), Fixture.app(3, "Chrome")],
            appMRU: [3, 1]
        )
        #expect(groups.map(\.app.pid) == [3, 1, 2])
    }

    @Test("ordering is total, so repeated passes are byte-identical")
    func stableOrdering() {
        let windows = [
            Fixture.window(12, pid: 1, title: "same"),
            Fixture.window(10, pid: 1, title: "same"),
            Fixture.window(11, pid: 1, title: "same"),
        ]
        let forward = AppGrouping.group(windows: windows, apps: [Fixture.app(1, "Code")])
        let reversed = AppGrouping.group(windows: windows.reversed(), apps: [Fixture.app(1, "Code")])
        #expect(forward[0].windows.map(\.id) == [10, 11, 12])
        #expect(forward[0].windows.map(\.id) == reversed[0].windows.map(\.id))
    }

    @Test("main window sorts first within an app")
    func mainFirst() {
        let groups = AppGrouping.group(
            windows: [
                Fixture.window(10, pid: 1, title: "zebra"),
                Fixture.window(11, pid: 1, title: "alpha", flags: .main),
            ],
            apps: [Fixture.app(1, "Code")]
        )
        #expect(groups[0].windows.map(\.title) == ["alpha", "zebra"])
    }

    @Test("windows of unknown pids are dropped")
    func dropsUnknownPIDs() {
        let groups = AppGrouping.group(
            windows: [Fixture.window(10, pid: 1), Fixture.window(99, pid: 42)],
            apps: [Fixture.app(1, "Code")]
        )
        #expect(groups[0].windows.map(\.id) == [10])
    }

    @Test("an app with no surviving windows produces no group")
    func noEmptyGroups() {
        let groups = AppGrouping.group(
            windows: [Fixture.window(10, pid: 1, flags: .minimized)],
            apps: [Fixture.app(1, "Code")],
            options: .init(includeMinimized: false)
        )
        #expect(groups.isEmpty)
    }

    @Test("collapsing native tabs keeps only the main one")
    func nativeTabs() {
        let tabs = [
            Fixture.window(10, pid: 1, title: "Downloads", flags: [.nativeTab, .main]),
            Fixture.window(11, pid: 1, title: "Projects", flags: .nativeTab),
        ]
        #expect(AppGrouping.group(windows: tabs, apps: [Fixture.app(1, "Finder")])[0].windows.count == 2)
        #expect(
            AppGrouping.group(
                windows: tabs,
                apps: [Fixture.app(1, "Finder")],
                options: .init(breakOutNativeTabs: false)
            )[0].windows.map(\.title) == ["Downloads"]
        )
    }
}

@Suite("FuzzyRank")
struct FuzzyRankTests {
    private var groups: [AppGroup] { Fixture.snapshot.groups }

    @Test("an exact title substring ranks first")
    func titleMatch() {
        #expect(FuzzyRank.rank(groups: groups, query: "dotfiles").first?.window.title == "dotfiles")
    }

    @Test("matching is a subsequence, not a substring")
    func subsequence() {
        #expect(FuzzyRank.rank(groups: groups, query: "dtfl").first?.window.title == "dotfiles")
    }

    @Test("app name and window title can be matched together")
    func crossFieldMatch() {
        let results = FuzzyRank.rank(groups: groups, query: "code api")
        #expect(results.first?.window.title == "api-server")
    }

    @Test("an empty query returns nothing, so callers fall back to the grouped view")
    func emptyQuery() {
        #expect(FuzzyRank.rank(groups: groups, query: "").isEmpty)
    }

    @Test("no match returns nothing rather than everything")
    func noMatch() {
        #expect(FuzzyRank.rank(groups: groups, query: "zzzzq").isEmpty)
    }

    @Test("matching is case-insensitive")
    func caseInsensitive() {
        #expect(FuzzyRank.rank(groups: groups, query: "GITHUB").first?.window.title == "GitHub")
    }

    @Test("equal scores keep MRU order, so results never jitter between keystrokes")
    func stableTiebreak() {
        let twice = (0..<2).map { _ in FuzzyRank.rank(groups: groups, query: "a").map(\.window.id) }
        #expect(twice[0] == twice[1])
    }
}

@Suite("TileSizing")
struct TileSizingTests {
    private let screen = CGSize(width: 1512, height: 982)

    @Test("a few tiles use the preferred width")
    func preferredWhenRoomy() {
        let layout = TileSizing.layout(count: 3, screen: screen)
        #expect(layout.tileSize.width == 220)
        #expect(layout.rows == 1)
    }

    @Test("many tiles shrink to stay on one row")
    func shrinksToFit() {
        let layout = TileSizing.layout(count: 8, screen: screen)
        #expect(layout.rows == 1)
        #expect(layout.tileSize.width < 220)
        #expect(layout.tileSize.width >= 120)
    }

    @Test("past the floor it wraps instead of shrinking into illegibility")
    func wrapsAtFloor() {
        let layout = TileSizing.layout(count: 40, screen: screen)
        #expect(layout.tileSize.width == 120)
        #expect(layout.rows > 1)
        #expect(layout.columns * layout.rows >= 40)
    }

    @Test("never exceeds the screen fraction it is allowed")
    func respectsScreenBudget() {
        for count in [1, 5, 12, 40] {
            let layout = TileSizing.layout(count: count, screen: screen)
            #expect(layout.contentSize.width <= screen.width * 0.8 + layout.tileSize.width)
        }
    }

    @Test("zero tiles is a valid empty layout, not a crash")
    func emptyLayout() {
        #expect(TileSizing.layout(count: 0, screen: screen).columns == 0)
    }

    @Test("configured width is clamped to a usable range")
    func clamping() {
        #expect(TileSizing.Metrics.clampedWidth(9999) == 400)
        #expect(TileSizing.Metrics.clampedWidth(10) == 120)
    }
}

@Suite("DwellPolicy")
struct DwellPolicyTests {

    @Test("delayed mode reports its delay")
    func delayed() {
        #expect(DwellPolicy(mode: .delayed(.milliseconds(300))).delay == .milliseconds(300))
    }

    @Test("instant and manual arm no timer, for opposite reasons")
    func noTimerModes() {
        #expect(DwellPolicy(mode: .instant).delay == nil)
        #expect(DwellPolicy(mode: .instant).firesAutomatically)
        #expect(DwellPolicy(mode: .manual).delay == nil)
        #expect(!DwellPolicy(mode: .manual).firesAutomatically)
    }

    @Test("delay is clamped to a range where the feature still works")
    func clamping() {
        #expect(DwellPolicy.clampedDelay(milliseconds: 0) == .milliseconds(150))
        #expect(DwellPolicy.clampedDelay(milliseconds: 99_999) == .milliseconds(2000))
        #expect(DwellPolicy.clampedDelay(milliseconds: 500) == .milliseconds(500))
    }
}

@Suite("ThumbKeyDerivation")
struct ThumbKeyTests {

    @Test("a document URL yields a strong key that survives renames")
    func strongKey() {
        let key = ThumbKeyDerivation.key(
            bundleID: "com.apple.TextEdit", documentURL: "file:///notes.txt", title: "notes", pid: 1)
        #expect(key.isStrong)
    }

    @Test("without a document it falls back to a weak title key")
    func weakKey() {
        let key = ThumbKeyDerivation.key(
            bundleID: "com.apple.finder", documentURL: nil, title: "Downloads", pid: 1)
        #expect(!key.isStrong)
    }

    @Test("the same title in two apps yields different keys")
    func namespacedByApp() {
        let finder = ThumbKeyDerivation.key(bundleID: "com.apple.finder", documentURL: nil, title: "X", pid: 1)
        let chrome = ThumbKeyDerivation.key(bundleID: "com.google.Chrome", documentURL: nil, title: "X", pid: 2)
        #expect(finder != chrome)
    }

    @Test("keys are 128-bit hex")
    func keyShape() {
        let key = ThumbKeyDerivation.key(bundleID: "a", documentURL: nil, title: "b", pid: 1)
        #expect(key.hex.count == 32)
        #expect(key.hex.allSatisfy { $0.isHexDigit })
    }
}
