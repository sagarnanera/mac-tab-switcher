import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let demoMode: Bool
    private var environment: AppEnvironment?

    init(demoMode: Bool = false) {
        self.demoMode = demoMode
        super.init()
    }
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A switcher has no business in the Dock or the app switcher it replaces.
        NSApp.setActivationPolicy(.accessory)

        // Deliberately NOT gated on Accessibility. The app is usable without it —
        // titles come from the Window Server and raising goes through the private
        // front-process call — so blocking startup would trade a working switcher for
        // a permission dialog. The prompt is fired once, and a grant arriving later is
        // picked up by the poll below.
        launch()
        if !AXPermission.isTrusted(prompting: true) {
            watchForAccessibilityGrant()
        }
    }

    private func launch() {
        let environment = AppEnvironment()
        environment.start()
        self.environment = environment
        installStatusItem()

        // WindowServer refuses synthesised modifier keystrokes, so the overlay cannot
        // be triggered programmatically. This exists so it can still be inspected and
        // screenshotted during development.
        // Development aid: opening Settings normally goes through the menu bar, which
        // cannot be driven without Automation permission.
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }

        Task {
            // Long enough for discovery and the thumbnail seed to finish: reporting
            // before the seed made every row look like a capture failure.
            try? await Task.sleep(for: .seconds(4))
            await Self.writeStatusReport(environment)
            if demoMode {
                environment.controller.summonForDemo()
                // Reveals the strip a few seconds later so the collapsed and expanded
                // layouts can be compared: the app row must not move between them.
                if CommandLine.arguments.contains("--demo-strip") {
                    try? await Task.sleep(for: .seconds(4))
                    environment.controller.revealStripForDemo()
                }
            }
            if CommandLine.arguments.contains("--test-activate") {
                await Self.testLevelTwoActivation(environment)
            }
            if CommandLine.arguments.contains("--test-minimized") {
                await Self.testMinimizedCapture(environment)
            }
        }
    }

    /// There is no notification for a TCC grant, so polling is the only option. Once
    /// it lands, a refresh picks up everything accessibility adds: minimized and main
    /// state, native tabs, and elements for raising.
    private func watchForAccessibilityGrant() {
        Task { [weak self] in
            while !AXPermission.isTrusted() {
                try? await Task.sleep(for: .seconds(1))
            }
            guard let environment = self?.environment else { return }
            self?.refreshStatusItem()
            await environment.store.refresh()
            await Self.writeStatusReport(environment)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: "TabSwitcher"
        )
        image?.isTemplate = true
        item.button?.image = image
        // Survives a menu bar so crowded that the icon is pushed under the notch: the
        // item stays in the overflow list and can still be reached, and the tooltip
        // names it when it is.
        item.button?.toolTip = "TabSwitcher"
        item.behavior = []
        item.isVisible = true
        statusItem = item
        refreshStatusItem()
    }

    /// Both permissions are optional and each one only removes a capability, so the
    /// menu says which are missing and what that costs rather than demanding them.
    private func refreshStatusItem() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        if !AXPermission.isTrusted() {
            menu.addItem(withTitle: "Accessibility off — no minimized or tab detection",
                         action: #selector(openAccessibilitySettings), keyEquivalent: "")
        }
        if !CGPreflightScreenCaptureAccess() {
            menu.addItem(withTitle: "Screen Recording off — showing icons, not previews",
                         action: #selector(openScreenRecordingSettings), keyEquivalent: "")
        }
        if AXPermission.isTrusted(), CGPreflightScreenCaptureAccess() {
            menu.addItem(withTitle: "All permissions granted", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        // Targeted explicitly rather than left to the responder chain: an accessory
        // app whose only window is a non-activating panel has no reliable chain for a
        // nil-target menu item to travel up.
        menu.addItem(withTitle: "Quit TabSwitcher", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }
        item.menu = menu
    }

    /// Exercises the level-two path directly: pick an app with several windows and
    /// activate one that is *not* its frontmost, which is the case the app exists for
    /// and the only one a hotkey cannot be scripted to reproduce.
    private static func testLevelTwoActivation(_ environment: AppEnvironment) async {
        var log = ""
        let snapshot = await environment.store.current
        guard let group = snapshot.groups.first(where: { $0.windows.count > 1 }) else {
            try? "no app with more than one window".write(
                toFile: "/tmp/tabswitcher-activate.txt", atomically: true, encoding: .utf8)
            return
        }

        for (index, window) in group.windows.enumerated().dropFirst() {
            let element = await environment.store.element(for: window.id)
            log += "\n--- target \(index): \"\(window.title)\" id \(window.id)\n"
            log += "    ax element: \(element == nil ? "MISSING" : "present")\n"
            let probed = AXWindowReader.probeRemoteWindowIDs(pid: window.pid)
            log += "    brute force found ids: \(probed.sorted().prefix(12).map(String.init).joined(separator: ", "))\n"
            log += "    target in that set: \(probed.contains(window.id))\n"
            log += "    flags: minimized=\(window.flags.contains(.minimized)) "
            log += "otherSpace=\(window.flags.contains(.otherSpace)) "
            log += "main=\(window.flags.contains(.main))\n"

            let outcome = await environment.activator.activate(window)
            log += "    outcome: \(outcome)\n"

            let app = AXElement.application(pid: window.pid)
            app.setMessagingTimeout(0.5)
            let focusedTitle = app.copyElement(kAXFocusedWindowAttribute as String)?.title ?? "(none)"
            let focusedID = app.copyElement(kAXFocusedWindowAttribute as String)?.windowID
            log += "    app's focused window now: \"\(focusedTitle)\" id \(focusedID.map(String.init) ?? "?")\n"
            log += "    matches target: \(focusedID == window.id)\n"
            try? await Task.sleep(for: .milliseconds(500))
        }

        let header = """
            level-two activation test
            app: \(group.app.name) (\(group.windows.count) windows)
            frontmost window per grouping: "\(group.frontmost.title)"

            """
        try? (header + log).write(
            toFile: "/tmp/tabswitcher-activate.txt", atomically: true, encoding: .utf8)
    }

    /// Verifies the central claim behind using the private capture path at all:
    /// pixels for a **minimized** window. ScreenCaptureKit structurally cannot do this
    /// — its stream pauses while a window is minimized — so if this fails there is no
    /// reason to accept the risk of a private symbol.
    ///
    /// Uses a throwaway TextEdit window so no real work is disturbed.
    private static func testMinimizedCapture(_ environment: AppEnvironment) async {
        var log = "minimized capture test\n\n"

        guard let textEdit = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.TextEdit") else {
            log += "TextEdit not found\n"
            try? log.write(toFile: "/tmp/tabswitcher-minimized.txt", atomically: true, encoding: .utf8)
            return
        }
        // Open an actual document: launching TextEdit bare gives its Open dialog,
        // which is not a minimizable window and made an earlier version of this test
        // pass without ever minimizing anything.
        let scratch = URL(fileURLWithPath: "/tmp/tabswitcher-minimize-probe.txt")
        try? "minimized capture probe".write(to: scratch, atomically: true, encoding: .utf8)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.open([scratch], withApplicationAt: textEdit,
                                               configuration: configuration)
        try? await Task.sleep(for: .seconds(3))

        await environment.store.refresh()
        var snapshot = await environment.store.current
        guard let group = snapshot.groups.first(where: { $0.app.bundleID == "com.apple.TextEdit" }),
              let window = group.windows.first(where: { $0.title.contains("probe") })
                ?? group.windows.first else {
            log += "no TextEdit window appeared; apps seen: "
            log += snapshot.groups.map(\.app.name).joined(separator: ", ") + "\n"
            try? log.write(toFile: "/tmp/tabswitcher-minimized.txt", atomically: true, encoding: .utf8)
            return
        }
        log += "window: \"\(window.title)\" id \(window.id)\n"

        let capturer: any WindowCapturer = SkyLightCapturer.isAvailable
            ? SkyLightCapturer() : ScreenCaptureKitCapturer()
        log += "capturer: \(capturer.name)\n\n"

        let before = await capturer.capture(windowID: window.id, maxPixelWidth: 400)
        log += "visible:   \(before.map { "\($0.width)x\($0.height)" } ?? "NO IMAGE")\n"

        guard let element = await environment.store.element(for: window.id) else {
            log += "no ax element, cannot minimize\n"
            try? log.write(toFile: "/tmp/tabswitcher-minimized.txt", atomically: true, encoding: .utf8)
            return
        }
        let minimizeResult = element.set(kAXMinimizedAttribute as String, kCFBooleanTrue)
        log += "AXMinimized write: \(minimizeResult == .success ? "ok" : "failed (\(minimizeResult.rawValue))")\n"
        try? await Task.sleep(for: .seconds(2))

        await environment.store.refresh()
        snapshot = await environment.store.current
        let reported = snapshot.groups
            .first { $0.app.bundleID == "com.apple.TextEdit" }?
            .windows.first { $0.id == window.id }
        log += "flagged minimized: \(reported?.flags.contains(.minimized) ?? false)\n"

        let after = await capturer.capture(windowID: window.id, maxPixelWidth: 400)
        log += "minimized: \(after.map { "\($0.width)x\($0.height)" } ?? "NO IMAGE")\n\n"
        let actuallyMinimized = reported?.flags.contains(.minimized) ?? false
        if !actuallyMinimized {
            log += "INCONCLUSIVE — the window never minimized, so this proves nothing\n"
        } else {
            log += after != nil
                ? "PASS — minimized windows have capturable pixels\n"
                : "FAIL — no pixels while minimized; the private path buys nothing here\n"
        }

        element.set(kAXMinimizedAttribute as String, kCFBooleanFalse)
        try? await Task.sleep(for: .seconds(1))
        NSRunningApplication(processIdentifier: window.pid)?.terminate()

        try? log.write(toFile: "/tmp/tabswitcher-minimized.txt", atomically: true, encoding: .utf8)
    }

    /// Returns to accessory mode once Settings closes, so the app leaves no Dock icon
    /// behind.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func openSettings() {
        guard let environment else { return }
        // An accessory app cannot reliably bring a window to the front — it has no Dock
        // presence for macOS to activate. Becoming a regular app for as long as the
        // window is open is the supported way round it; the policy reverts on close so
        // the Dock icon does not linger.
        NSApp.setActivationPolicy(.regular)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TabSwitcher Settings"
        window.contentView = NSHostingView(
            rootView: SettingsView(preferences: environment.preferences) { [weak environment] in
                environment?.applyPreferences()
            }
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static let statusReportPath = "/tmp/tabswitcher-status.txt"

    /// Writes what the *running app* sees, from inside its own TCC identity.
    ///
    /// The `--diagnose` command-line mode cannot answer this: launched from a shell,
    /// macOS attributes permissions to the terminal that started it, so it reports the
    /// terminal's grants rather than the app's. Anything permission-dependent has to be
    /// measured in here, which is why this runs on every launch and not only in demo
    /// mode.
    private static func writeStatusReport(_ environment: AppEnvironment) async {
        let snapshot = await environment.store.current
        let timings = await environment.store.timings
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \(String(format: "%.0f", $0.value.seconds * 1000))ms" }
            .joined(separator: ", ")
        var report = """
            discovery: \(timings)

            accessibility:    \(AXPermission.isTrusted() ? "granted" : "NOT granted")
            screen recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "NOT granted")

            window server: \(CGWindowList.candidates().count) candidates, \
            \(CGWindowList.candidates().filter { !$0.title.isEmpty }.count) titled

            snapshot: \(snapshot.groups.count) apps
            ([img] = preview cached. Strip windows stay blank until an app is expanded.)

            """
        for group in snapshot.groups {
            report += "\(group.app.name) (\(group.windows.count))\n"
            for window in group.windows {
                let thumb = await environment.thumbnails.cached(window.thumbKey) != nil ? "img" : "---"
                report += "    [\(thumb)] \(window.title)\n"
            }
        }
        try? report.write(toFile: statusReportPath, atomically: true, encoding: .utf8)
    }

    @objc private func copyDiagnostics() {
        let report = """
            TabSwitcher diagnostics

            accessibility: \(AXPermission.isTrusted() ? "granted" : "not granted")
            secure input: \(SecureInput.isEnabled ? "active" : "inactive")

            private API availability:
            \(Diagnostics.capabilityReport())
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
