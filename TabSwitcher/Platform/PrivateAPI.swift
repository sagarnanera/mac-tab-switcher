import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Types the private interfaces speak

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

/// Options for `CGSHWCaptureWindowList`. Values reverse-engineered by the window-manager
/// community; documented here because nothing else documents them.
struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    /// Capture the window's own bounds, ignoring any clipping the compositor applies.
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    /// On Retina, 1 point becomes 1 pixel — a quarter of the pixels of `bestResolution`.
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    /// Stage Manager skews captures without this.
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

/// `_SLPSSetFrontProcessWithOptions` mode. 0x200 = "as if the user did it", which is
/// what makes macOS switch Spaces to follow the window.
enum SLPSMode: UInt32 {
    case userGenerated = 0x200
}

/// Every private symbol the app can use, resolved once at launch.
///
/// **Why `dlsym` and not `@_silgen_name`.** `@_silgen_name` links the symbol at build
/// time, so if a future macOS removes it the app fails to *launch* — dyld kills the
/// process before `main`. `dlsym` resolves at runtime and hands back nil, which lets
/// every caller fall back to a public API and keeps the app running with one degraded
/// feature instead of none.
///
/// That is the entire firewall: nothing outside this file touches a private symbol,
/// every capability is queryable via ``has``, and every call site has a public
/// alternative. `Diagnostics` reports which ones resolved.
enum PrivateAPI {

    // MARK: Resolution

    private nonisolated(unsafe) static let skyLight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let skyLight, let found = dlsym(skyLight, name) { return found }
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)   // RTLD_DEFAULT
    }

    enum Capability: String, CaseIterable {
        case windowIDFromAX = "_AXUIElementGetWindow"
        case captureWindows = "CGSHWCaptureWindowList"
        case spacesForWindows = "CGSCopySpacesForWindows"
        case managedDisplaySpaces = "CGSCopyManagedDisplaySpaces"
        case setFrontProcess = "_SLPSSetFrontProcessWithOptions"
        case postEventRecord = "SLPSPostEventRecordTo"
        case processSerialNumber = "GetProcessForPID"
        case remoteToken = "_AXUIElementCreateWithRemoteToken"
    }

    static func has(_ capability: Capability) -> Bool {
        switch capability {
        case .windowIDFromAX: getWindowFn != nil
        case .captureWindows: captureFn != nil && connectionFn != nil
        case .spacesForWindows: spacesForWindowsFn != nil && connectionFn != nil
        case .managedDisplaySpaces: managedSpacesFn != nil && connectionFn != nil
        case .setFrontProcess: setFrontProcessFn != nil && processForPIDFn != nil
        case .postEventRecord: postEventFn != nil && processForPIDFn != nil
        case .processSerialNumber: processForPIDFn != nil
        case .remoteToken: remoteTokenFn != nil
        }
    }

    static var availability: [String: Bool] {
        Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0.rawValue, has($0)) })
    }

    // MARK: Function pointers

    private typealias ConnectionFn = @convention(c) () -> CGSConnectionID
    private typealias CaptureFn = @convention(c) (
        CGSConnectionID, UnsafePointer<CGWindowID>, UInt32, UInt32
    ) -> Unmanaged<CFArray>?
    private typealias SpacesForWindowsFn = @convention(c) (
        CGSConnectionID, Int32, CFArray
    ) -> Unmanaged<CFArray>?
    private typealias ManagedSpacesFn = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    private typealias GetWindowFn = @convention(c) (
        AXUIElement, UnsafeMutablePointer<CGWindowID>
    ) -> AXError
    private typealias SetFrontProcessFn = @convention(c) (
        UnsafePointer<ProcessSerialNumber>, CGWindowID, UInt32
    ) -> CGError
    private typealias PostEventFn = @convention(c) (
        UnsafePointer<ProcessSerialNumber>, UnsafePointer<UInt8>
    ) -> CGError
    private typealias RemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias ProcessForPIDFn = @convention(c) (
        pid_t, UnsafeMutablePointer<ProcessSerialNumber>
    ) -> OSStatus

    private nonisolated(unsafe) static let connectionFn: ConnectionFn? =
        symbol("CGSMainConnectionID").map { unsafeBitCast($0, to: ConnectionFn.self) }
    private nonisolated(unsafe) static let captureFn: CaptureFn? =
        symbol("CGSHWCaptureWindowList").map { unsafeBitCast($0, to: CaptureFn.self) }
    private nonisolated(unsafe) static let spacesForWindowsFn: SpacesForWindowsFn? =
        symbol("CGSCopySpacesForWindows").map { unsafeBitCast($0, to: SpacesForWindowsFn.self) }
    private nonisolated(unsafe) static let managedSpacesFn: ManagedSpacesFn? =
        symbol("CGSCopyManagedDisplaySpaces").map { unsafeBitCast($0, to: ManagedSpacesFn.self) }
    private nonisolated(unsafe) static let getWindowFn: GetWindowFn? =
        symbol("_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindowFn.self) }
    private nonisolated(unsafe) static let setFrontProcessFn: SetFrontProcessFn? =
        symbol("_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: SetFrontProcessFn.self) }
    private nonisolated(unsafe) static let postEventFn: PostEventFn? =
        symbol("SLPSPostEventRecordTo").map { unsafeBitCast($0, to: PostEventFn.self) }
    private nonisolated(unsafe) static let remoteTokenFn: RemoteTokenFn? =
        symbol("_AXUIElementCreateWithRemoteToken").map { unsafeBitCast($0, to: RemoteTokenFn.self) }

    /// Swift marks `GetProcessForPID` unavailable (deprecated before 10.9), but the
    /// private front-process calls below take a `ProcessSerialNumber` and nothing
    /// modern produces one. The symbol is still exported, so it is resolved the same
    /// way as everything else here.
    private nonisolated(unsafe) static let processForPIDFn: ProcessForPIDFn? =
        symbol("GetProcessForPID").map { unsafeBitCast($0, to: ProcessForPIDFn.self) }

    private nonisolated(unsafe) static let connection: CGSConnectionID? = connectionFn?()

    private static func processSerialNumber(for pid: pid_t) -> ProcessSerialNumber? {
        guard let processForPIDFn else { return nil }
        var psn = ProcessSerialNumber()
        guard processForPIDFn(pid, &psn) == noErr else { return nil }
        return psn
    }

    // MARK: - Wrapped operations

    /// The `CGWindowID` behind an accessibility element. No public API exposes this.
    /// Fallback when unavailable: match on (pid, title, frame), which is what
    /// `WindowMatcher` does.
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindowFn else { return nil }
        var id: CGWindowID = 0
        guard getWindowFn(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// Snapshot windows straight out of the compositor's backing store.
    ///
    /// The reason this is worth the risk: it returns pixels for **minimized and
    /// off-Space windows**, which ScreenCaptureKit structurally cannot — its stream
    /// pauses for a minimized window. This is the same path the Dock uses for its own
    /// hover previews.
    static func captureWindows(_ ids: [CGWindowID], bestResolution: Bool) -> [CGImage]? {
        guard let captureFn, let connection, !ids.isEmpty else { return nil }
        var options: CGSWindowCaptureOptions = [.ignoreGlobalClipShape, .fullSize]
        options.insert(bestResolution ? .bestResolution : .nominalResolution)
        return ids.withUnsafeBufferPointer { buffer -> [CGImage]? in
            guard let base = buffer.baseAddress,
                  let result = captureFn(connection, base, UInt32(ids.count), options.rawValue)
            else { return nil }
            return result.takeRetainedValue() as? [CGImage]
        }
    }

    /// Which Spaces a window belongs to.
    ///
    /// The mask is 7 (`current | others | user`) and must not be widened: broader
    /// masks silently return nothing for windows on other Spaces, which is the exact
    /// case this call exists to answer.
    static func spaces(for windowIDs: [CGWindowID]) -> [CGSSpaceID] {
        guard let spacesForWindowsFn, let connection, !windowIDs.isEmpty else { return [] }
        let boxed = windowIDs.map { NSNumber(value: $0) } as CFArray
        guard let result = spacesForWindowsFn(connection, 7, boxed) else { return [] }
        return (result.takeRetainedValue() as? [NSNumber])?.map { $0.uint64Value } ?? []
    }

    /// Space ids currently visible across all displays.
    static func visibleSpaceIDs() -> Set<CGSSpaceID> {
        guard let managedSpacesFn, let connection,
              let displays = managedSpacesFn(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var visible: Set<CGSSpaceID> = []
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let id = current["ManagedSpaceID"] as? NSNumber else { continue }
            visible.insert(id.uint64Value)
        }
        return visible
    }

    /// Bring a process forward *and* raise one specific window of it, switching Spaces
    /// if needed. The public cooperative-activation APIs raise the app but not a chosen
    /// window, which is the entire problem this app exists to solve.
    @discardableResult
    static func setFrontProcess(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcessFn, var psn = processSerialNumber(for: pid) else { return false }
        return setFrontProcessFn(&psn, windowID, SLPSMode.userGenerated.rawValue) == .success
    }

    /// Make a window *key* (able to receive typing), which fronting alone does not do.
    ///
    /// Synthesises a click by posting a raw Window Server event record. The byte
    /// offsets are an undocumented struct layout, originally worked out by Hammerspoon.
    /// The click lands at (-1, -1) — just outside the frame — deliberately: clicking
    /// inside hit-tests the window's content, and at the top-left corner that means
    /// pressing the close button of Chrome PWA shims.
    @discardableResult
    static func makeKeyWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let postEventFn, var psn = processSerialNumber(for: pid) else { return false }

        var bytes = [UInt8](repeating: 0, count: 0xF8)
        bytes[0x04] = 0xF8
        bytes[0x3A] = 0x10
        var id = windowID
        withUnsafeBytes(of: &id) { bytes.replaceSubrange(0x3C..<0x40, with: $0) }
        var point = CGPoint(x: -1, y: -1)
        withUnsafeBytes(of: &point) { bytes.replaceSubrange(0x20..<0x30, with: $0) }

        var ok = true
        bytes[0x08] = 0x01                                   // mouse down
        ok = ok && bytes.withUnsafeBufferPointer { postEventFn(&psn, $0.baseAddress!) } == .success
        bytes[0x08] = 0x02                                   // mouse up
        ok = ok && bytes.withUnsafeBufferPointer { postEventFn(&psn, $0.baseAddress!) } == .success
        return ok
    }

    /// Fabricates an accessibility element for a window the normal AX window list will
    /// not return — in practice, windows on other Spaces.
    ///
    /// The token is an undocumented 20-byte structure: pid, two zero words, the literal
    /// 'coco', then the element id. Callers probe ids in a range; see `AXWindowReader`
    /// for why that is gated rather than routine.
    static func remoteElement(pid: pid_t, elementID: UInt64) -> AXUIElement? {
        guard let remoteTokenFn else { return nil }
        var token = Data(count: 20)
        var pid = pid
        var zero = Int32(0)
        var magic = Int32(0x636F_636F)                       // 'coco'
        var elementID = elementID
        withUnsafeBytes(of: &pid) { token.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: &zero) { token.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: &magic) { token.replaceSubrange(8..<12, with: $0) }
        withUnsafeBytes(of: &elementID) { token.replaceSubrange(12..<20, with: $0) }
        return remoteTokenFn(token as CFData)?.takeRetainedValue()
    }
}
