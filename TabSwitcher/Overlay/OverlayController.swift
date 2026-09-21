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
final class OverlayController {
    private let model: OverlayModel
    private let store: WindowStore
    private let thumbnails: ThumbnailStore
    private let activator: WindowActivator
    private let hotkeys: HotkeyMonitor

    private var panel: OverlayPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private var dwellTask: Task<Void, Never>?
    private var policy = DwellPolicy.default

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
        case .arrow(.down): dispatch(.enterStrip)
        case .arrow(.up): dispatch(.leaveStrip)
        case .arrow(.right): dispatch(.nextWindow)
        case .arrow(.left): dispatch(.previousWindow)
        }
    }

    private func dispatch(_ input: OverlayInput) {
        let effects = model.state.apply(input)
        for effect in effects { perform(effect) }
        if !effects.isEmpty { resize() }
    }

    // MARK: - Effects

    private func perform(_ effect: OverlayEffect) {
        switch effect {
        case .show:
            hotkeys.setSessionActive(true)
            show()

        case .hide:
            hotkeys.setSessionActive(false)
            cancelDwell()
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
    private func preparePanel() {
        let panel = OverlayPanel()
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderOut(nil)
        self.panel = panel
        self.hostingView = hosting
    }

    private func show() {
        guard let panel else { return }
        resize()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func resize() {
        guard let panel, let hosting = hostingView, panel.isVisible || model.state.isVisible else { return }
        let size = hosting.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return }
        let screen = targetScreen().visibleFrame
        panel.setFrame(
            NSRect(
                x: screen.midX - size.width / 2,
                y: screen.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
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
