import AppKit
import CoreGraphics
import SwitcherCore

/// `--diagnose` prints what resolved and what the discovery pass found, then exits.
///
/// Exists because every private symbol has a public fallback, so "is the degraded path
/// active?" must be answerable without launching a UI — for a bug report, for CI on a
/// future macOS, and for checking a build on a machine where permissions differ.
if CommandLine.arguments.contains("--diagnose") {
    print("accessibility:    \(AXPermission.isTrusted() ? "granted" : "NOT granted")")
    print("screen recording: \(CGPreflightScreenCaptureAccess() ? "granted" : "NOT granted")")
    print("secure input:     \(SecureInput.isEnabled ? "active" : "inactive")")
    print("capture via:      \(SkyLightCapturer.isAvailable ? "SkyLight (private)" : "ScreenCaptureKit (fallback)")")

    // Separates "the filter is too aggressive" from "the Window Server is withholding
    // titles because Screen Recording is denied" — the two look identical downstream.
    let raw = CGWindowList.candidates()
    let titled = raw.filter { !$0.title.isEmpty }
    print("")
    print("window server: \(raw.count) candidate surfaces, \(titled.count) with a title")
    let untitled = raw.filter { $0.title.isEmpty }
    if !untitled.isEmpty {
        print("  dropped for having no title (accessibility would supply one):")
        for candidate in untitled.prefix(12) {
            let name = NSRunningApplication(processIdentifier: candidate.pid)?.localizedName ?? "pid \(candidate.pid)"
            print("    \(name)  \(Int(candidate.frame.width))x\(Int(candidate.frame.height))")
        }
    }

    if CommandLine.arguments.contains("--audit") {
        print("")
        print("every titled surface the window server reports:")
        for row in CGWindowList.audit() where !row.candidate.title.isEmpty {
            let name = NSRunningApplication(processIdentifier: row.candidate.pid)?.localizedName ?? "?"
            let mark = row.passed ? "keep" : "DROP"
            let size = "\(Int(row.candidate.frame.width))x\(Int(row.candidate.frame.height))"
            print("  \(mark) \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(size.padding(toLength: 10, withPad: " ", startingAt: 0)) \(row.reason.isEmpty ? "" : "(\(row.reason)) ")\(row.candidate.title)")
        }
    }

    // Capture self-test: proves whether the thumbnail pipeline produces pixels,
    // independently of whether the overlay manages to draw them.
    print("")
    print("capture self-test:")
    let capturer: any WindowCapturer = SkyLightCapturer.isAvailable
        ? SkyLightCapturer() : ScreenCaptureKitCapturer()
    for candidate in titled.prefix(5) {
        let name = NSRunningApplication(processIdentifier: candidate.pid)?.localizedName ?? "?"
        if let image = await capturer.capture(windowID: candidate.id, maxPixelWidth: 800) {
            print("  ok       \(name) — \(image.width)x\(image.height)")
        } else {
            print("  NO IMAGE \(name) — \(candidate.title)")
        }
    }
    print("")
    print("private symbols:")
    print(Diagnostics.capabilityReport().split(separator: "\n").map { "  \($0)" }.joined(separator: "\n"))
    print("")

    let result = await WindowDiscovery.run()
    for (label, duration) in result.timings.sorted(by: { $0.key < $1.key }) {
        print(String(format: "  %-14s %6.1fms", (label as NSString).utf8String!, duration.seconds * 1000))
    }
    // Round-trip test: warm() then read back the way the overlay reads, to separate
    // "capture failed" from "the view never sees the image".
    let store = ThumbnailStore()
    let groups = AppGrouping.group(windows: result.windows, apps: result.apps)
    let frontmost = groups.map(\.frontmost)
    await store.warm(frontmost)
    let hits = frontmost.filter { store.cached($0.thumbKey) != nil }.count
    print("")
    print("warm/read round-trip: \(hits)/\(frontmost.count) app tiles have an image after warm()")

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
let delegate = AppDelegate(demoMode: CommandLine.arguments.contains("--demo"))
application.delegate = delegate
application.run()
