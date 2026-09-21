import AppKit
import SwiftUI

/// Hosts the first-run flow.
///
/// Separate from Settings because the two answer different questions: Settings is "how
/// do I change this", welcome is "what is this and why does it want my permissions".
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: WelcomeModel
    private let onClose: () -> Void

    init(hotkeyDescription: String, modifierDescription: String, onClose: @escaping () -> Void) {
        self.model = WelcomeModel(
            hotkeyDescription: hotkeyDescription, modifierDescription: modifierDescription)
        self.onClose = onClose
        super.init()
    }

    /// Called when the overlay is summoned, so the last step can confirm the shortcut
    /// genuinely works rather than assuming it.
    func noteOverlayAppeared() {
        model.noteOverlayAppeared()
    }

    var isOpen: Bool { window?.isVisible ?? false }

    /// Development aid: jump straight to a step, since the flow otherwise needs clicks.
    func show(startingAt step: WelcomeModel.Step? = nil) {
        if let step { model.step = step }
        model.refreshPermissions()
        if let window {
            present(window)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView(model: model) { [weak self] in
            self?.window?.close()
        })
        // After the content view is installed: setting this earlier is undone when the
        // titlebar's accessory view is rebuilt.
        //
        // The window is neither resizable nor minimizable, so both buttons are
        // permanently dead. A control that looks pressable and does nothing is worse
        // than no control, so they are removed rather than left greyed out.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        // An accessory app has no Dock presence for macOS to activate, so it has to
        // become a regular app for as long as a window is up.
        NSApp.setActivationPolicy(.regular)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onClose()
    }
}
