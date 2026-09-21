import AppKit

/// The borderless window the switcher draws into.
///
/// `.nonactivatingPanel` is the key choice: the panel can take keyboard focus without
/// activating our application, so the app you are switching *from* stays frontmost
/// until you actually commit. That is what lets the cooperative activation in
/// `WindowActivator` name a sensible source app.
final class OverlayPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        // Above context menus. `.screenSaver` is higher still but interferes with
        // other system UI for no benefit here.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    /// Required for keyboard input. `canBecomeMain` stays false so we never steal
    /// "main window" status from the app underneath.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
