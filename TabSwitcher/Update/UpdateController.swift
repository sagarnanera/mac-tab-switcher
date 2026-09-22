import AppKit
import Sparkle

/// Auto-updates.
///
/// Thin on purpose. Sparkle's standard controller already owns the whole flow — check,
/// download, verify, relaunch — and every line of ours that reimplements part of it is a
/// line that can disagree with the framework about what state the update is in.
///
/// What is *not* delegated is the decision to check at all. `SUEnableAutomaticChecks` is
/// false in Info.plist, so Sparkle asks on second launch rather than assuming consent to
/// download and run code.
@MainActor
final class UpdateController: NSObject {

    private let controller: SPUStandardUpdaterController

    /// Whether Sparkle looks for updates on its own. Mirrored into Settings rather than
    /// left only in Sparkle's own prompt, because a user who said no once should be able
    /// to find the switch again without reinstalling.
    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    override init() {
        // startingUpdater: true wires the whole thing up at launch. The scheduled check
        // costs nothing until the interval elapses, and doing it later means holding a
        // half-initialised updater around for no gain.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Menu and Settings both point here. Sparkle puts up its own window, which needs the
    /// app to be visible: an accessory app has no Dock presence, so a check started from
    /// the menu bar would otherwise show its progress behind whatever is frontmost.
    func checkForUpdates() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }
}
