import AppKit
import CoreGraphics
import Observation

/// State for the first-run flow.
///
/// Permission status is polled rather than cached: there is no notification for a TCC
/// grant, and the user leaves the app to grant one, so the window has to notice on its
/// own when they come back.
@MainActor
@Observable
final class WelcomeModel {

    enum Step: Int, CaseIterable {
        case welcome, permissions, gesture, tryIt

        var title: String {
            switch self {
            case .welcome: "Welcome to TabSwitcher"
            case .permissions: "Two permissions"
            case .gesture: "One key does everything"
            case .tryIt: "Try it"
            }
        }
    }

    var step: Step = .welcome
    private(set) var accessibility = AXPermission.isTrusted()
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    /// Set when the overlay is actually summoned, which is the only honest proof that
    /// the shortcut works end to end.
    private(set) var sawOverlay = false

    /// The whole shortcut, e.g. "⌥Tab".
    var hotkeyDescription: String
    /// Only the modifiers, e.g. "⌥", for copy about holding them. Derived separately
    /// rather than trimmed off the full description, which silently mangles any key
    /// name longer than one character.
    var modifierDescription: String

    init(hotkeyDescription: String, modifierDescription: String) {
        self.hotkeyDescription = hotkeyDescription
        self.modifierDescription = modifierDescription
    }

    var isFirstStep: Bool { step == .welcome }
    var isLastStep: Bool { step == .tryIt }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func refreshPermissions() {
        accessibility = AXPermission.isTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
    }

    func noteOverlayAppeared() {
        sawOverlay = true
    }

    /// Asking triggers the system prompt the first time only; afterwards macOS shows
    /// nothing at all, so the pane is opened as well. Doing both is the only way the
    /// button reliably leads somewhere.
    func requestAccessibility() {
        _ = AXPermission.isTrusted(prompting: true)
        open("Privacy_Accessibility")
    }

    /// Screen Recording never re-prompts once declined, so this only opens the pane.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        open("Privacy_ScreenCapture")
    }

    private func open(_ pane: String) {
        NSWorkspace.shared.open(URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
