import AppKit
import ApplicationServices
import CoreGraphics

/// Permission state and the deep links that let a user fix it.
///
/// Both grants are one-shot at the OS level: `AXIsProcessTrustedWithOptions` prompts
/// once per code identity, and `CGRequestScreenCaptureAccess` shows nothing at all
/// once a decline has been recorded. So neither can be the only path — the panes must
/// always be reachable directly.
enum Permissions {
    static var accessibility: Bool { AXWindowReader.isTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    @MainActor
    static func request() {
        if !accessibility {
            _ = AXWindowReader.isTrusted(prompting: true)
            open(.accessibility)
        }
        if !screenRecording {
            // Returns false immediately and shows nothing if the user already
            // declined once — which is why the pane is opened regardless.
            _ = CGRequestScreenCaptureAccess()
            open(.screenRecording)
        }
    }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
    }

    @MainActor
    static func open(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
