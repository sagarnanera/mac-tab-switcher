import ApplicationServices
import CoreGraphics
import Foundation

/// A thread-safe box around `AXUIElement`.
///
/// `AXUIElement` is a CoreFoundation type: safe to retain and message from any thread,
/// but carrying no `Sendable` conformance and never going to get one. This box is the
/// single place in the codebase where that unsafety is asserted.
final class AXElement: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t

    init(_ element: AXUIElement, pid: pid_t) {
        self.element = element
        self.pid = pid
    }

    static func application(pid: pid_t) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid), pid: pid)
    }

    // MARK: - Reads

    /// All reads funnel through here so every call feeds the responsiveness breaker.
    private func copy(_ attribute: String) -> CFTypeRef? {
        guard !AXResponsiveness.shared.isUnresponsive(pid) else { return nil }
        var value: CFTypeRef?
        let clock = ContinuousClock()
        let start = clock.now
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        AXResponsiveness.shared.record(pid: pid, error: error, elapsed: clock.now - start)
        return error == .success ? value : nil
    }

    func string(_ attribute: String) -> String? { copy(attribute) as? String }
    func bool(_ attribute: String) -> Bool { copy(attribute) as? Bool ?? false }

    /// Single-element attributes such as `kAXFocusedWindow` return one element rather
    /// than an array.
    func copyElement(_ attribute: String) -> AXElement? {
        guard let raw = copy(attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return AXElement(raw as! AXUIElement, pid: pid)
    }

    func elements(_ attribute: String) -> [AXElement] {
        guard let raw = copy(attribute) as? [AXUIElement] else { return [] }
        return raw.map { AXElement($0, pid: pid) }
    }

    /// `AXValue` boxes structs and needs an out-param unwrap rather than a cast.
    /// Returns the fallback rather than trapping when an app reports the wrong type,
    /// which they occasionally do.
    private func structValue<T>(_ attribute: String, _ kind: AXValueType, fallback: T) -> T {
        guard let raw = copy(attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return fallback }
        var out = fallback
        guard AXValueGetValue(raw as! AXValue, kind, &out) else { return fallback }
        return out
    }

    var frame: CGRect {
        CGRect(
            origin: structValue(kAXPositionAttribute as String, .cgPoint, fallback: .zero),
            size: structValue(kAXSizeAttribute as String, .cgSize, fallback: .zero)
        )
    }

    var title: String { string(kAXTitleAttribute as String) ?? "" }
    var subrole: String? { string(kAXSubroleAttribute as String) }
    var role: String? { string(kAXRoleAttribute as String) }
    var isMinimized: Bool { bool(kAXMinimizedAttribute as String) }
    var isMain: Bool { bool(kAXMainAttribute as String) }
    var documentURL: String? { string(kAXDocumentAttribute as String) }

    /// Present when the window has real window chrome. Used as an escape hatch for
    /// apps whose subrole is non-standard but which are plainly real windows.
    var hasCloseButton: Bool { copy(kAXCloseButtonAttribute as String) != nil }
    var hasMinimizeButton: Bool { copy(kAXMinimizeButtonAttribute as String) != nil }

    var windowID: CGWindowID? { PrivateAPI.windowID(of: element) }

    // MARK: - Writes

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    /// Bounds how long any single call may block this thread. The default is ~6s,
    /// which a busy app will happily consume.
    func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }
}

enum AXPermission {
    static func isTrusted(prompting: Bool = false) -> Bool {
        // The constant `kAXTrustedCheckOptionPrompt` is an unannotated mutable global,
        // which Swift 6 strict concurrency rejects. Its value is this literal.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompting] as CFDictionary)
    }
}
