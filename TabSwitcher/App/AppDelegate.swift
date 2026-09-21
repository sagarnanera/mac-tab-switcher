import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        Task {
            // Long enough for discovery and the thumbnail seed to finish: reporting
            // before the seed made every row look like a capture failure.
            try? await Task.sleep(for: .seconds(4))
            await Self.writeStatusReport(environment)
            if demoMode { environment.controller.summonForDemo() }
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
        menu.addItem(withTitle: "Copy diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
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
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable],
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
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        // An accessory app's windows open behind everything unless it activates.
        NSApp.activate()
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
        var report = """
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
