import AppKit
import CoreGraphics
import ServiceManagement
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
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A switcher has no business in the Dock or the app switcher it replaces.
        NSApp.setActivationPolicy(.accessory)

        // Deliberately NOT gated on Accessibility. The app is usable without it —
        // titles come from the Window Server and raising goes through the private
        // front-process call — so blocking startup would trade a working switcher for
        // a permission dialog. The prompt is fired once, and a grant arriving later is
        // picked up by the poll below.
        launch()

        // First run gets the guided flow, which asks for Accessibility in context.
        // Afterwards the bare system prompt is enough, since the user has already been
        // told what it is for.
        if let environment, !environment.preferences.hasSeenWelcome {
            showWelcome()
        } else if !AXPermission.isTrusted(prompting: true) {
            watchForAccessibilityGrant()
        }
        if !AXPermission.isTrusted() {
            watchForAccessibilityGrant()
        }
    }

    @objc private func showWelcome() {
        guard let environment else { return }
        if welcome == nil {
            let controller = WelcomeWindowController(
                hotkeyDescription: environment.hotkeyDescription,
                modifierDescription: environment.modifierDescription
            ) { [weak self] in
                self?.environment?.preferences.hasSeenWelcome = true
                self?.refreshStatusItem()
            }
            // Lets the last step confirm the shortcut really summons the overlay.
            environment.controller.onSummon = { [weak controller] in
                controller?.noteOverlayAppeared()
            }
            welcome = controller
        }
        let requested = CommandLine.arguments
            .firstIndex(of: "--welcome-step")
            .flatMap { CommandLine.arguments.indices.contains($0 + 1) ? Int(CommandLine.arguments[$0 + 1]) : nil }
            .flatMap(WelcomeModel.Step.init(rawValue:))
        welcome?.show(startingAt: requested)
    }

    /// Computed once. `codesign --verify --deep` on a 5MB bundle is not free, and the
    /// answer cannot change while the app is running — a bundle replaced underneath a
    /// live process is a different problem than this one.
    private lazy var bundleIntegrity: BundleIntegrity.Result = {
        #if DEBUG
        // A debug build is re-signed on every build and lives in DerivedData, where a
        // stale manifest means nothing.
        return .valid
        #else
        return BundleIntegrity.verify()
        #endif
    }()

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
            if CommandLine.arguments.contains("--test-login-item") {
                Self.testLoginItem()
            }
            if CommandLine.arguments.contains("--dump-a11y") {
                // SwiftUI has not laid out the strip at the instant the reveal is
                // dispatched, and the accessibility tree is built from the layout — the
                // same "read back the previous layout" hazard that sized the panel wrong.
                try? await Task.sleep(for: .seconds(1))
                Self.dumpAccessibilityTree()
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
        // A dedicated glyph, not the app icon shrunk down: the menu bar is monochrome
        // and 18pt, where a detailed colour icon turns to mush. Template rendering lets
        // macOS own the colour so it adapts to light, dark and accent tinting.
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        image?.isTemplate = true
        image?.accessibilityDescription = "TabSwitcher"
        item.button?.image = image
        item.button?.toolTip = "TabSwitcher"
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

        // A lapsed permission gets a badge rather than a window. macOS re-prompts for
        // Screen Recording roughly monthly, and a setup window reappearing unbidden a
        // month later would be worse than the lapse it is reporting.
        let missing = !AXPermission.isTrusted() || !CGPreflightScreenCaptureAccess()
        item.button?.toolTip = missing
            ? "TabSwitcher — a permission is missing"
            : "TabSwitcher"
        if #available(macOS 14, *) {
            item.button?.contentTintColor = missing ? .systemOrange : nil
        }

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
        if case .broken = bundleIntegrity {
            // Ahead of everything else: while this is true, nothing below it works
            // properly and every other entry is a distraction.
            menu.addItem(withTitle: "Damaged install — permissions will not work",
                         action: #selector(explainBrokenBundle), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Setup guide…", action: #selector(showWelcome), keyEquivalent: "")
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

    /// Says what broke and what to do, rather than leaving the user to conclude the app
    /// stopped finding windows for no reason. Re-signing in place is deliberately not
    /// offered: an app that repairs its own signature is indistinguishable from one
    /// being tampered with.
    @objc private func explainBrokenBundle() {
        guard case .broken(let detail) = bundleIntegrity else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "This copy of TabSwitcher is damaged"
        alert.informativeText = """
            Its code signature no longer verifies. macOS ties Accessibility and Screen \
            Recording to that signature, so those permissions will be refused even though \
            System Settings still shows them as granted — the app will appear to have \
            stopped working for no reason.

            Reinstalling fixes it. Your settings are kept.

            \(detail)
            """
        alert.addButton(withTitle: "Copy Details")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(detail, forType: .string)
        }
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

    /// `--settings appearance` opens straight to a pane. Several settings can only be
    /// judged by looking at them, and a script cannot click a sidebar row.
    private static func requestedSettingsPane() -> SettingsView.Pane {
        guard let index = CommandLine.arguments.firstIndex(of: "--settings"),
              CommandLine.arguments.indices.contains(index + 1),
              let pane = SettingsView.Pane(rawValue: CommandLine.arguments[index + 1])
        else { return .general }
        return pane
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
            rootView: SettingsView(
                preferences: environment.preferences,
                initialPane: Self.requestedSettingsPane()
            ) { [weak environment] in
                environment?.applyPreferences()
            }
        )
        window.center()
        window.isReleasedWhenClosed = false
        // macOS otherwise restores the window's last state across launches, so Settings
        // reopens on whichever pane was last viewed weeks ago rather than at the start.
        window.isRestorable = false
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
    /// Registers and unregisters the login item, reporting what the system said.
    ///
    /// `SMAppService.mainApp` describes the *calling* bundle, so this cannot be checked
    /// from a script or a test binary — only from inside the app, which is why it is a
    /// flag rather than a unit test. It also depends on where the app is installed: a
    /// bundle in a temporary or non-standard location registers and then silently fails
    /// to launch, so the path is reported alongside the status.
    private static func testLoginItem() {
        func status() -> String {
            switch SMAppService.mainApp.status {
            case .enabled: "enabled"
            case .requiresApproval: "requiresApproval (user must allow it in System Settings)"
            case .notRegistered: "notRegistered"
            case .notFound: "notFound"
            @unknown default: "unknown"
            }
        }

        var report = "login item test\n\n"
        report += "bundle:  \(Bundle.main.bundlePath)\n"
        report += "initial: \(status())\n"

        let wasEnabled = LaunchAtLogin.isEnabled

        if let error = LaunchAtLogin.set(true) {
            report += "register FAILED: \(error)\n"
        } else {
            report += "after register: \(status())  isEnabled=\(LaunchAtLogin.isEnabled)"
            report += "  needsApproval=\(LaunchAtLogin.needsApproval)\n"
        }

        if let error = LaunchAtLogin.set(false) {
            report += "unregister FAILED: \(error)\n"
        } else {
            report += "after unregister: \(status())  isEnabled=\(LaunchAtLogin.isEnabled)\n"
        }

        // Left as it was found: a diagnostic that changes a user setting is a bug.
        if wasEnabled { _ = LaunchAtLogin.set(true) }
        report += "restored to: \(status())\n"

        try? report.write(toFile: "/tmp/tabswitcher-loginitem.txt", atomically: true, encoding: .utf8)
    }

    /// Walks the overlay's own accessibility tree and writes what a screen reader would
    /// find there.
    ///
    /// The alternative is switching VoiceOver on, which starts talking over whatever the
    /// machine is doing and cannot run in CI. This asks the same question of the same
    /// API: SwiftUI's accessibility modifiers are only a promise until something reads
    /// them back out, and a tile whose label never reached the AX layer looks identical
    /// in the source to one that did.
    private static func dumpAccessibilityTree() {
        var report = "overlay accessibility tree, as a screen reader would walk it\n\n"
        var labelled = 0

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 12 else { return }
            func string(_ attribute: String) -> String? {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
                else { return nil }
                return value as? String
            }
            let role = string(kAXRoleAttribute) ?? "?"
            let label = string(kAXDescriptionAttribute) ?? string(kAXTitleAttribute) ?? ""
            if !label.isEmpty {
                labelled += 1
                report += String(repeating: "  ", count: depth) + "\(role)  \(label)\n"
            }

            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
                  let list = children as? [AXUIElement] else { return }
            for child in list { walk(child, depth: depth + 1) }
        }

        walk(AXUIElementCreateApplication(getpid()), depth: 0)
        report += "\n\(labelled) labelled elements\n"
        try? report.write(toFile: "/tmp/tabswitcher-a11y.txt", atomically: true, encoding: .utf8)
    }

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
                let thumb = environment.thumbnails.cached(window.thumbKey) != nil ? "img" : "---"
                report += "    [\(thumb)] \(window.title)\n"
            }
        }
        try? report.write(toFile: statusReportPath, atomically: true, encoding: .utf8)
    }
}
