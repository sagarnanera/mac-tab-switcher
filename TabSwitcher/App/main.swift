import AppKit
import SwitcherCore

/// `--diagnose` prints what resolved and what the discovery pass found, then exits.
///
/// Exists because every private symbol has a public fallback, so "is the degraded path
/// active?" must be answerable without launching a UI — for a bug report, for CI on a
/// future macOS, and for checking a build on a machine where permissions differ.
if CommandLine.arguments.contains("--diagnose") {
    print("accessibility: \(AXPermission.isTrusted() ? "granted" : "NOT granted")")
    print("secure input:  \(SecureInput.isEnabled ? "active" : "inactive")")
    print("capture via:   \(SkyLightCapturer.isAvailable ? "SkyLight (private)" : "ScreenCaptureKit (fallback)")")
    print("")
    print("private symbols:")
    print(Diagnostics.capabilityReport().split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
    print("")

    let result = await WindowDiscovery.run()
    for (label, duration) in result.timings.sorted(by: { $0.key < $1.key }) {
        print(String(format: "  %-14s %6.1fms", (label as NSString).utf8String!, duration.seconds * 1000))
    }
    let groups = AppGrouping.group(windows: result.windows, apps: result.apps)
    print("")
    print("\(groups.count) apps, \(result.windows.count) windows")
    for group in groups {
        print("\(group.app.name)\(group.isExpandable ? "  ⧉\(group.windows.count)" : "")")
        for window in group.windows {
            var marks: [String] = []
            if window.flags.contains(.main) { marks.append("main") }
            if window.flags.contains(.minimized) { marks.append("min") }
            if window.flags.contains(.nativeTab) { marks.append("tab") }
            if window.flags.contains(.otherSpace) { marks.append("other-space") }
            let badge = marks.isEmpty ? "" : "  [\(marks.joined(separator: ","))]"
            print("    \(window.title)\(badge)")
        }
    }
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
