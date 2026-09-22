import AppKit
import SwiftUI
import SwitcherCore

/// Drives the overlay: feeds input into the state machine and performs the effects it
/// returns.
///
/// Deliberately the only place that knows about both the pure model and AppKit. The
/// state machine decides *what* should happen; this decides *how*, and neither has to
/// know about the other's concerns.
@MainActor
final class OverlayController: NSObject {
    private let model: OverlayModel
    private let store: WindowStore
    private let thumbnails: ThumbnailStore
    private let activator: WindowActivator
    private let hotkeys: HotkeyMonitor

    private var panel: OverlayPanel?
    private var hosting: NSHostingController<OverlayView>?
    private var dwellTask: Task<Void, Never>?
    /// Screen-space Y of the panel's top edge for the current session.
    ///
    /// The strip reveals *below* the app row, so the panel grows downward. Re-centring
    /// on every resize moved the app row up under a user who was still deciding, which
    /// breaks the rule that the row they are aiming at must not move. Pinning the top
    /// edge keeps the row exactly where it was.
    private var anchorTop: CGFloat?
    private var policy = DwellPolicy.default
    /// Fired whenever the overlay is shown. The welcome flow uses it to confirm the
    /// shortcut actually works, rather than telling the user it does and hoping.
    var onSummon: (() -> Void)?

    init(
        model: OverlayModel,
        store: WindowStore,
        thumbnails: ThumbnailStore,
        activator: WindowActivator,
        hotkeys: HotkeyMonitor
    ) {
        self.model = model
        self.store = store
        self.thumbnails = thumbnails
        self.activator = activator
        self.hotkeys = hotkeys
        super.init()
    }

    func setDwellPolicy(_ policy: DwellPolicy) {
        self.policy = policy
    }

    func start() {
        preparePanel()
        hotkeys.start { [weak self] event in
            // The tap runs on its own thread; all state lives on the main actor.
            Task { @MainActor in self?.handle(event) }
        }
    }

    func apply(snapshot: WindowSnapshot) {
        dispatch(.snapshotChanged(snapshot))
    }

    // MARK: - Input

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .summon:
            activator.rememberFront()
            model.secureInputWarning = SecureInput.isEnabled
            dispatch(.summon)
        case .cycleForward: dispatch(.nextApp)
        case .cycleBackward: dispatch(.previousApp)
        case .modifiersReleased: dispatch(.modifierReleased)
        case .confirm: dispatch(.confirm)
        case .cancel: dispatch(.cancel)
        case .deleteBackward: dispatch(.deleteBackward)
        case .character(let character): dispatch(.typed(character))
        case .selectWindow(let index): dispatch(.selectWindow(index))
        case .arrow(.down): dispatch(.enterStrip)
        case .arrow(.up): dispatch(.leaveStrip)
        case .arrow(.right): dispatch(.nextWindow)
        case .arrow(.left): dispatch(.previousWindow)
        }
    }

    /// Reads the state out, mutates the copy, then assigns it back.
    ///
    /// Not cosmetic. Calling a `mutating` method directly on `model.state` goes through
    /// the `_modify` accessor, which `@Observable` does not instrument — so SwiftUI
    /// never learns the value changed and the overlay renders its first frame and
    /// nothing after it. An explicit assignment invokes the setter and emits the
    /// change. Every in-place mutation of an observable's value-type property has this
    /// hazard.
    private func dispatch(_ input: OverlayInput) {
        var next = model.state
        let effects = next.apply(input)
        model.state = next
        for effect in effects { perform(effect) }
        if !effects.isEmpty { resize() }
    }

    // MARK: - Effects

    private func perform(_ effect: OverlayEffect) {
        switch effect {
        case .show:
            hotkeys.setSessionActive(true)
            show()
            onSummon?()

        case .hide:
            hotkeys.setSessionActive(false)
            cancelDwell()
            anchorTop = nil
            panel?.orderOut(nil)

        case .armDwell:
            armDwell()

        case .cancelDwell:
            cancelDwell()

        case .activate(let window):
            Task { [activator] in
                let outcome = await activator.activate(window)
                if case .failed(let reason) = outcome {
                    Diagnostics.log("activation failed: \(reason)")
                }
            }

        case .restorePreviousFocus:
            activator.restorePreviousFocus()

        case .wantThumbnails(let windows):
            Task { [thumbnails, model] in
                await thumbnails.warm(windows)
                await MainActor.run { model.thumbnailGeneration &+= 1 }
            }
        }
    }

    // MARK: - Dwell

    /// The timer is driven here rather than in the state machine so the machine stays
    /// pure and testable; its expiry comes back in as an ordinary input.
    private func armDwell() {
        cancelDwell()
        guard policy.firesAutomatically else { return }

        guard let delay = policy.delay else {
            dispatch(.dwellElapsed)          // .instant
            return
        }

        model.showsDwellProgress = true
        model.dwellProgress = 0
        dwellTask = Task { [weak self] in
            let steps = 30
            let step = delay / steps
            for index in 1...steps {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled else { return }
                self?.model.dwellProgress = Double(index) / Double(steps)
            }
            guard !Task.isCancelled else { return }
            self?.dispatch(.dwellElapsed)
            self?.model.showsDwellProgress = false
        }
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
        model.dwellProgress = 0
        model.showsDwellProgress = false
    }

    // MARK: - Panel

    /// Built once at launch and merely re-shown afterwards. Creating a window and its
    /// hosting view on the hotkey would put SwiftUI's first-render cost directly in the
    /// path the user feels.
    ///
    /// Uses `NSHostingController` with `.preferredContentSize` rather than a bare
    /// `NSHostingView`: AppKit then resizes the window whenever SwiftUI's preferred
    /// size changes. Measuring the view ourselves right after mutating state reads the
    /// size of the *previous* layout — SwiftUI has not re-laid-out yet — which sized
    /// the panel to whatever it held last and clipped everything else away.
    private func preparePanel() {
        let panel = OverlayPanel()
        let hosting = NSHostingController(
            rootView: OverlayView(model: model) { [weak self] input in
                self?.dispatch(input)
            }
        )
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        panel.delegate = self
        panel.alphaValue = 0
        panel.orderOut(nil)
        self.panel = panel
        self.hosting = hosting
    }

    /// Shows the overlay. Public so a demo/screenshot mode can drive it without a
    /// synthesised keystroke, which WindowServer refuses to deliver anyway.
    func summonForDemo() {
        activator.rememberFront()
        dispatch(.summon)
    }

    /// Demo hook: selects the first expandable app and steps into its window strip.
    /// Demo hook: selects the first expandable app and steps into its window strip, so
    /// the collapsed and expanded layouts can be compared without a keystroke.
    func revealStripForDemo() {
        if let index = model.state.groups.firstIndex(where: { $0.isExpandable }) {
            dispatch(.hover(app: index, window: nil))
        }
        dispatch(.enterStrip)
    }

    private func show() {
        guard let panel else { return }
        // Centre once, for the collapsed layout, then keep that top edge for the rest
        // of the session.
        anchorTop = nil
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        reposition()
        announce()
    }

    /// Tells a screen reader what just took the keyboard.
    ///
    /// An overlay that appears, swallows every keystroke and says nothing is
    /// indistinguishable from the machine having locked up. Posted as an announcement
    /// rather than relying on focus moving, because the panel is deliberately
    /// non-activating: our application never becomes frontmost, so there is no focus
    /// change for VoiceOver to follow.
    private func announce() {
        let state = model.state
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: TileNarration.summary(
                    appCount: state.groups.count,
                    windowCount: state.groups.reduce(0) { $0 + $1.windows.count }
                ),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    /// Only ever repositions; the size belongs to AppKit and SwiftUI.
    fileprivate func reposition() {
        guard let panel, panel.isVisible else { return }
        let screen = targetScreen().visibleFrame
        let size = panel.frame.size
        guard size.height > 1 else { return }

        let top: CGFloat
        if let anchorTop {
            top = anchorTop
        } else {
            top = screen.midY + size.height / 2
            self.anchorTop = top
        }
        // If growing downward would run off the bottom of the screen, slide the whole
        // panel up and re-anchor there rather than clipping the strip.
        var origin = NSPoint(x: screen.midX - size.width / 2, y: top - size.height)
        if origin.y < screen.minY {
            origin.y = screen.minY
            anchorTop = origin.y + size.height
        }
        panel.setFrameOrigin(origin)
    }

    private func resize() {
        reposition()
    }

    /// `NSScreen.main` has not meant "the screen with the key window" since 10.9 and
    /// returns the first screen in several common cases, so the mouse's screen is used
    /// instead — it is where the user is looking.
    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.screens.first
            ?? NSScreen.main!
    }
}

extension OverlayController: NSWindowDelegate {
    /// The panel grows and shrinks as the window strip reveals and collapses. Keeping
    /// it centred here rather than at dispatch time means the reposition always uses
    /// the size AppKit actually applied.
    func windowDidResize(_ notification: Notification) {
        reposition()
    }
}
