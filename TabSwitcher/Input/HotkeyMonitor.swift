import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The keyboard shortcut that summons the switcher.
struct Hotkey: Sendable, Equatable, Codable {
    var keyCode: UInt16
    /// `CGEventFlags` raw value, masked to the modifiers we care about.
    var modifiers: UInt64

    /// Option+Tab. Deliberately not Command+Tab: that chord is consumed by the Dock
    /// inside the Window Server, and taking it over requires a private call that leaves
    /// the user's Command+Tab broken if the app ever crashes without restoring it.
    static let `default` = Hotkey(
        keyCode: UInt16(kVK_Tab), modifiers: CGEventFlags.maskAlternate.rawValue
    )

    static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    /// Whether this event is the cycle chord.
    ///
    /// Shift is ignored when comparing, because Shift is the *direction* modifier:
    /// ⌥⇧Tab must still register as the cycle key so it can reverse. Requiring an exact
    /// modifier match meant ⌥⇧Tab matched nothing at all and reverse cycling silently
    /// did nothing. When the user's own shortcut includes Shift there is no direction
    /// modifier left, so it is compared exactly.
    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard self.keyCode == keyCode else { return false }
        let required = CGEventFlags(rawValue: modifiers)
        let pressed = flags.intersection(Self.relevantModifiers)
        guard !required.contains(.maskShift) else { return pressed == required }
        return pressed.subtracting(.maskShift) == required
    }

    /// Whether every modifier this hotkey requires is still held.
    func modifiersStillHeld(_ flags: CGEventFlags) -> Bool {
        let required = CGEventFlags(rawValue: modifiers)
        return required.intersection(Self.relevantModifiers).isSubset(of: flags)
    }
}

enum HotkeyEvent: Sendable {
    case summon
    case cycleForward
    case cycleBackward
    case modifiersReleased
    case arrow(Arrow)
    /// ⌥ plus a digit: jump straight to that window of the selected app.
    case selectWindow(Int)
    case confirm
    case cancel
    case character(Character)
    case deleteBackward

    enum Arrow: Sendable { case up, down, left, right }
}

/// Watches the keyboard for the hotkey and everything that follows it.
///
/// One tap handles both the summon chord and the in-session keys, because the session
/// needs to consume keystrokes that would otherwise reach the app underneath — you do
/// not want the arrow keys you use to pick a window also scrolling the document behind
/// the overlay.
final class HotkeyMonitor: @unchecked Sendable {
    private var tap: CFMachPort?
    private let lock = NSLock()
    private var hotkey: Hotkey = .default
    private var sessionActive = false
    private var handler: (@Sendable (HotkeyEvent) -> Void)?

    /// Set while the overlay is up, so the tap knows to consume navigation keys.
    func setSessionActive(_ active: Bool) {
        lock.lock()
        sessionActive = active
        lock.unlock()
    }

    func setHotkey(_ hotkey: Hotkey) {
        lock.lock()
        self.hotkey = hotkey
        lock.unlock()
    }

    @discardableResult
    func start(handler: @escaping @Sendable (HotkeyEvent) -> Void) -> Bool {
        self.handler = handler

        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // .defaultTap, not .listenOnly: the session must be able to swallow keys.
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        EventTapThread.shared.add(CFMachPortCreateRunLoopSource(nil, tap, 0))
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Taps are disabled by the system on timeout or heavy user input, and stay
        // dead until explicitly re-armed. Without this the switcher silently stops
        // working partway through a session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let hotkey = self.hotkey
        let active = sessionActive
        lock.unlock()

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged {
            // Secure Input filters keyDown out of every tap system-wide but leaves
            // flagsChanged alone, so modifier tracking keeps working even when a
            // password field is focused.
            if active, !hotkey.modifiersStillHeld(flags) {
                emit(.modifiersReleased)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        if hotkey.matches(keyCode: keyCode, flags: flags) {
            emit(active ? (flags.contains(.maskShift) ? .cycleBackward : .cycleForward) : .summon)
            return nil
        }
        guard active else { return Unmanaged.passUnretained(event) }

        // Digits jump directly to a window while the strip is open. Checked before the
        // character handler so a jump is never mistaken for search input; with the
        // modifier held these keys produce symbols anyway, not digits.
        if let index = Self.digitIndex(keyCode) {
            emit(.selectWindow(index))
            return nil
        }

        switch Int(keyCode) {
        case kVK_Escape: emit(.cancel); return nil
        case kVK_Return, kVK_ANSI_KeypadEnter: emit(.confirm); return nil
        case kVK_UpArrow: emit(.arrow(.up)); return nil
        case kVK_DownArrow: emit(.arrow(.down)); return nil
        case kVK_LeftArrow: emit(.arrow(.left)); return nil
        case kVK_RightArrow: emit(.arrow(.right)); return nil
        case kVK_Delete: emit(.deleteBackward); return nil
        default: break
        }

        if let character = Self.character(from: event), !character.isNewline {
            emit(.character(character))
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func emit(_ event: HotkeyEvent) {
        handler?(event)
    }

    /// Physical digit keys 1-9, by key code rather than by character: the character a
    /// digit key produces changes with the modifier held and with the keyboard layout.
    private static func digitIndex(_ keyCode: UInt16) -> Int? {
        let digits: [Int: Int] = [
            kVK_ANSI_1: 0, kVK_ANSI_2: 1, kVK_ANSI_3: 2, kVK_ANSI_4: 3, kVK_ANSI_5: 4,
            kVK_ANSI_6: 5, kVK_ANSI_7: 6, kVK_ANSI_8: 7, kVK_ANSI_9: 8,
        ]
        return digits[Int(keyCode)]
    }

    private static func character(from event: CGEvent) -> Character? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0, let scalar = String(utf16CodeUnits: buffer, count: length).first,
              !scalar.isWhitespace || scalar == " " else { return nil }
        return scalar
    }
}

enum SecureInput {
    /// While any process holds secure input, key events are filtered out of every tap
    /// system-wide. Typing to filter stops working; the modifier-release path does not.
    /// Surfacing this is the difference between "the app is broken" and "1Password has
    /// your keyboard".
    static var isEnabled: Bool { IsSecureEventInputEnabled() }
}
