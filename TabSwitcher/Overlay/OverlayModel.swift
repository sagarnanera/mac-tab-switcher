import AppKit
import Observation
import SwitcherCore

/// What the SwiftUI overlay renders.
///
/// A single observable object rather than many: the overlay is redrawn as a unit, and
/// spreading state across several observables makes SwiftUI's dependency tracking do
/// more work than the whole render is worth.
@MainActor
@Observable
final class OverlayModel {
    var state = OverlayState()
    var metrics = TileSizing.Metrics.default
    /// Bumped whenever thumbnails land, to pull fresh images out of the store without
    /// making every tile observe the cache individually.
    var thumbnailGeneration = 0
    /// Progress of the pending dwell, 0...1. Drives the bar under the selected tile
    /// that teaches the reveal gesture exists.
    var dwellProgress: Double = 0
    var showsDwellProgress = false
    var secureInputWarning = false
    /// Whether to draw the key hints. Warnings are shown regardless — an overlay that
    /// silently stops responding to typing, with nothing explaining why, reads as
    /// broken rather than restricted.
    var showsKeyboardHints = true

    private let thumbnails: ThumbnailStore
    private var iconCache: [pid_t: NSImage] = [:]

    init(thumbnails: ThumbnailStore) {
        self.thumbnails = thumbnails
    }

    func thumbnail(for window: WindowEntry) -> CGImage? {
        _ = thumbnailGeneration
        return thumbnails.cached(window.thumbKey)?.image
    }

    /// Icons are cached because `NSRunningApplication.icon` is a surprisingly expensive
    /// first read and the app row asks for one per tile on every frame.
    func icon(for app: AppRef) -> NSImage? {
        if let cached = iconCache[app.pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: app.pid)?.icon else { return nil }
        iconCache[app.pid] = icon
        return icon
    }
}
