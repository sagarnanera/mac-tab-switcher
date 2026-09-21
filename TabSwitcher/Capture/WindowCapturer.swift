import CoreGraphics
import Foundation
import ScreenCaptureKit
import SwitcherCore

/// Produces pixels for a window.
protocol WindowCapturer: Sendable {
    var name: String { get }
    /// Whether this capturer can produce an image for a window with no on-screen
    /// presence — minimized, hidden, or on another Space.
    var handlesOffscreenWindows: Bool { get }
    func capture(windowID: CGWindowID, maxPixelWidth: Int) async -> CGImage?
}

/// Reads the compositor's own backing store — the same path the Dock uses for its
/// hover previews.
///
/// Chosen as the primary because it is the only way to get pixels for a **minimized**
/// window. ScreenCaptureKit structurally cannot: its stream pauses while a window is
/// minimized, so there is nothing to capture. Every macOS switcher that shows
/// minimized previews uses this call.
struct SkyLightCapturer: WindowCapturer {
    let name = "SkyLight"
    let handlesOffscreenWindows = true
    var bestResolution: Bool = true

    static var isAvailable: Bool { PrivateAPI.has(.captureWindows) }

    func capture(windowID: CGWindowID, maxPixelWidth: Int) async -> CGImage? {
        guard let image = PrivateAPI.captureWindows([windowID], bestResolution: bestResolution)?.first
        else { return nil }
        // The compositor will hand back a fully transparent frame for a window mid
        // Space-transition, or one that has not drawn yet. Showing it is worse than
        // showing nothing, because it reads as a broken tile rather than a missing one.
        guard !CaptureValidation.isBlank(image) else { return nil }
        return CaptureValidation.downscaled(image, maxPixelWidth: maxPixelWidth)
    }
}

/// Public-API fallback for when the private capture symbol is unavailable.
///
/// Strictly worse — it cannot see minimized windows — but it keeps thumbnails working
/// at all if a future macOS removes the SkyLight entry point.
struct ScreenCaptureKitCapturer: WindowCapturer {
    let name = "ScreenCaptureKit"
    let handlesOffscreenWindows = false

    /// The entire capture happens inside one raced task: `SCWindow` is not `Sendable`,
    /// so it must never cross an isolation boundary, and `SCShareableContent.current`
    /// sporadically never returns (Apple FB12114396) so the whole thing needs a
    /// timeout rather than just the content fetch.
    func capture(windowID: CGWindowID, maxPixelWidth: Int) async -> CGImage? {
        try? await withThrowingTaskGroup(of: CGImage?.self) { group in
            group.addTask {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.windowID == windowID })
                else { return nil }

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let configuration = SCStreamConfiguration()
                // Width and height are in PIXELS. Setting them in points is the single
                // most common cause of blurry ScreenCaptureKit thumbnails.
                let aspect = max(filter.contentRect.height, 1) / max(filter.contentRect.width, 1)
                configuration.width = maxPixelWidth
                configuration.height = Int(CGFloat(maxPixelWidth) * aspect)
                configuration.scalesToFit = true
                configuration.preservesAspectRatio = true
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                if #available(macOS 14.2, *) {
                    // Keeps sheets and popovers out of the thumbnail.
                    configuration.includeChildWindows = false
                }
                return try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}

enum CaptureValidation {
    /// Samples a grid of pixels rather than scanning the whole image: a blank frame is
    /// blank everywhere, and this runs on every capture.
    static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return false }
        let length = CFDataGetLength(data)
        guard length > 0 else { return true }

        let samples = 64
        let stride = max(1, length / samples)
        var index = 0
        while index < length {
            if bytes[index] != 0 { return false }
            index += stride
        }
        return true
    }

    static func downscaled(_ image: CGImage, maxPixelWidth: Int) -> CGImage {
        guard image.width > maxPixelWidth, maxPixelWidth > 0 else { return image }
        let scale = CGFloat(maxPixelWidth) / CGFloat(image.width)
        let width = maxPixelWidth
        let height = max(1, Int(CGFloat(image.height) * scale))

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
