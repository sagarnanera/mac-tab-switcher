import ApplicationServices
import Foundation

/// `AXUIElement` is a CFType — safe to retain and message from any thread, but
/// carries no `Sendable` conformance and never will. This box is the only place
/// that unsafety is asserted.
///
/// Every element gets a 0.25s messaging timeout at construction. Without it, a call
/// into a beachballing app blocks the caller for the ~6s default, which is why all
/// AX work also runs off the main thread.
final class AXElementBox: @unchecked Sendable {
    let element: AXUIElement

    init(_ element: AXUIElement, timeout: Float = 0.25) {
        AXUIElementSetMessagingTimeout(element, timeout)
        self.element = element
    }

    static func application(pid: pid_t) -> AXElementBox {
        AXElementBox(AXUIElementCreateApplication(pid))
    }

    func rawAttribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    func attribute<T>(_ name: String, as type: T.Type = T.self) -> T? {
        rawAttribute(name) as? T
    }

    /// `AXValue` boxes structs (points, sizes) and needs an out-param unwrap rather
    /// than a cast. Returns nil rather than trapping when the attribute exists but
    /// holds something else — apps do occasionally lie about attribute types.
    func structAttribute<T>(_ name: String, _ kind: AXValueType, default fallback: T) -> T {
        guard let raw = rawAttribute(name), CFGetTypeID(raw) == AXValueGetTypeID() else {
            return fallback
        }
        var out = fallback
        guard AXValueGetValue(raw as! AXValue, kind, &out) else { return fallback }
        return out
    }

    func boolAttribute(_ name: String) -> Bool {
        attribute(name, as: Bool.self) ?? false
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }

    @discardableResult
    func setAttribute(_ name: String, _ value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }
}

/// Private but universally relied upon (AltTab, yabai, Rectangle all use it): maps an
/// `AXUIElement` window to the `CGWindowID` ScreenCaptureKit knows it by. There is no
/// public equivalent. `WindowInventory` falls back to matching on (pid, title, frame)
/// if this ever stops resolving.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXElementBox {
    var cgWindowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}
