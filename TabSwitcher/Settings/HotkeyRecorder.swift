import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records a keyboard shortcut.
///
/// Hand-rolled rather than pulled from a library because the app already owns a
/// system-wide event tap, and the one thing a recorder must do — capture keys without
/// them reaching anything else — is a local monitor, not a dependency.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var warning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(isRecording ? "Press a shortcut…" : Self.describe(hotkey))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 120, alignment: .leading)
                Button(isRecording ? "Cancel" : "Change") {
                    isRecording ? stop() : start()
                }
            }
            if let warning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        warning = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let modifiers = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                .intersection(Hotkey.relevantModifiers)

            // A shortcut with no modifier would fire on ordinary typing, and Command
            // alone is consumed by the Dock before any app sees it.
            guard !modifiers.isEmpty else {
                warning = "Add a modifier — a bare key would fire while you type."
                return nil
            }
            if modifiers == .maskCommand, event.keyCode == UInt16(kVK_Tab) {
                warning = "⌘Tab belongs to the Dock and cannot be taken over safely."
                return nil
            }
            hotkey = Hotkey(keyCode: event.keyCode, modifiers: modifiers.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func describe(_ hotkey: Hotkey) -> String {
        describeModifiers(hotkey) + keyName(hotkey.keyCode)
    }

    /// Just the modifiers, for copy that talks about holding them.
    static func describeModifiers(_ hotkey: Hotkey) -> String {
        let flags = CGEventFlags(rawValue: hotkey.modifiers)
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Tab: "Tab"
        case kVK_Space: "Space"
        case kVK_ANSI_Grave: "`"
        case kVK_Return: "Return"
        case kVK_Escape: "Esc"
        default: literal(keyCode)
        }
    }

    /// Resolves the key to whatever character the *current* layout produces, so the
    /// label matches the user's keyboard rather than a US one.
    private static func literal(_ keyCode: UInt16) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "key \(keyCode)" }

        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return -1
            }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, 4, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return "key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
