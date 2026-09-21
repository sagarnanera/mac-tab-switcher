import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A switcher has no business in the Dock or the app switcher it replaces.
        NSApp.setActivationPolicy(.accessory)

        guard AXPermission.isTrusted(prompting: true) else {
            presentPermissionGate()
            return
        }
        launch()
    }

    private func launch() {
        let environment = AppEnvironment()
        environment.start()
        self.environment = environment
        installStatusItem()
    }

    /// Accessibility cannot be granted without a relaunch in the general case, and
    /// polling for it is how the app avoids telling the user to do that.
    private func presentPermissionGate() {
        installStatusItem()
        Task { [weak self] in
            while !AXPermission.isTrusted() {
                try? await Task.sleep(for: .seconds(1))
            }
            self?.launch()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: "TabSwitcher"
        )
        let menu = NSMenu()
        menu.addItem(
            withTitle: AXPermission.isTrusted() ? "Accessibility granted" : "Waiting for Accessibility…",
            action: nil, keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Copy diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit TabSwitcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil && menuItem.action != #selector(NSApplication.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
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
