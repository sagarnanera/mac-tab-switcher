import AppKit
import TabCore

/// `--request` prompts for both permissions and opens the relevant System Settings
/// panes. Needed because neither grant can be driven reliably: the Accessibility
/// prompt fires once per code identity, and the Screen Recording prompt never
/// reappears after a single decline.
if CommandLine.arguments.contains("--request") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    await MainActor.run { Permissions.request() }
    print("accessibility:    \(Permissions.accessibility ? "granted" : "NOT granted")")
    print("screen recording: \(Permissions.screenRecording ? "granted" : "NOT granted")")
    print("")
    print("Add TabSwitcher.app in the panes that just opened, then re-run --dump.")
    exit(0)
}

/// `--raw` prints unfiltered ScreenCaptureKit output. Exists because the merge is
/// only as good as its input filter, and "which of these 206 surfaces is a window a
/// human would switch to" is not answerable from the docs.
if CommandLine.arguments.contains("--raw") {
    let inventory = WindowInventory()
    await inventory.dumpRaw()
    exit(0)
}

/// `--dump` prints the inventory and exits: the Phase 1 spike is about whether
/// enumeration and raising work, and neither needs a window to verify.
if CommandLine.arguments.contains("--dump") {
    let trusted = Permissions.accessibility
    let inventory = WindowInventory()
    let result = await inventory.enumerate()
    let described = await inventory.describedPIDs

    print("accessibility: \(trusted ? "granted" : "NOT granted")   screen recording: \(Permissions.screenRecording ? "granted" : "NOT granted")")
    for line in result.diagnostics { print("  \(line)") }
    print("")
    for group in result.groups {
        let mark = group.expandable ? " ⧉\(group.windows.count)" : ""
        print("\(group.app.localizedName)\(mark)")
        for window in group.windows {
            var marks: [String] = []
            if window.flags.contains(.main) { marks.append("main") }
            if window.flags.contains(.minimized) { marks.append("min") }
            if window.flags.contains(.nativeTab) { marks.append("tab") }
            if window.isLikelyOtherSpace(appWasDescribed: described.contains(window.pid)) {
                marks.append("other-space")
            } else if !window.flags.contains(.axCorroborated) {
                marks.append("no-ax")
            }
            let badge = marks.isEmpty ? "" : " [\(marks.joined(separator: ","))]"
            print("    \(window.title)\(badge)  (id \(window.windowID))")
        }
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let controller = InventoryWindowController()
controller.showWindow(nil)
app.activate()

app.run()
