import AppKit
import TabCore

/// `--dump` prints the inventory and exits: the Phase 1 spike is about whether
/// enumeration and raising work, and neither needs a window to verify.
if CommandLine.arguments.contains("--dump") {
    let trusted = AXWindowReader.isTrusted()
    let inventory = WindowInventory()
    let result = await inventory.enumerate()

    print("accessibility trusted: \(trusted)")
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
            if !window.flags.contains(.onCurrentSpace) { marks.append("other-space") }
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
