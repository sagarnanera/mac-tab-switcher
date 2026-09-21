import CoreGraphics
import Foundation
import ImageIO
import SwitcherCore
import UniformTypeIdentifiers

/// An immutable decoded image, safe to hand across isolation boundaries.
/// `CGImage` is thread-safe but carries no `Sendable` conformance.
final class ThumbnailImage: @unchecked Sendable {
    let image: CGImage
    let capturedAt: Date

    init(image: CGImage, capturedAt: Date = Date()) {
        self.image = image
        self.capturedAt = capturedAt
    }
}

/// Three tiers: decoded images in memory, JPEG on disk, and the capturer behind both.
///
/// The disk tier is what DockDoor lacks and is worth having: thumbnails survive a
/// relaunch, so the first summon after starting the app shows real previews instead of
/// a wall of placeholders.
actor ThumbnailStore {
    private let capturer: any WindowCapturer
    private let directory: URL
    private let maxPixelWidth: Int
    private let diskBudget: Int
    private let freshness: Duration

    /// Synchronously readable by the overlay. The hot path must never await, and must
    /// never touch the disk.
    private nonisolated let memory = MemoryTier()

    private var inFlight: Set<CGWindowID> = []

    init(
        capturer: (any WindowCapturer)? = nil,
        maxPixelWidth: Int = 800,
        diskBudget: Int = 256 * 1024 * 1024,
        freshness: Duration = .seconds(30)
    ) {
        self.capturer = capturer
            ?? (SkyLightCapturer.isAvailable ? SkyLightCapturer() : ScreenCaptureKitCapturer())
        self.maxPixelWidth = maxPixelWidth
        self.diskBudget = diskBudget
        self.freshness = freshness
        self.directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "dev.nanera.tabswitcher")
            .appending(path: "thumbnails")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated var capturerName: String { capturer.name }

    /// Zero-await read for the render path.
    nonisolated func cached(_ key: ThumbKey) -> ThumbnailImage? { memory.value(for: key.hex) }

    /// Fetches the windows whose tiles are on screen, most important first.
    ///
    /// Capture is bounded and de-duplicated: the compositor serialises these calls, so
    /// firing forty at once buys nothing and starves the ones the user is looking at.
    func warm(_ windows: [WindowEntry], limit: Int = 12) async {
        let wanted = windows.prefix(limit).filter { needsCapture($0) }
        guard !wanted.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for window in wanted {
                guard !inFlight.contains(window.id) else { continue }
                inFlight.insert(window.id)
                running += 1
                group.addTask { await self.captureAndStore(window) }
                if running >= 4 {
                    await group.next()
                    running -= 1
                }
            }
        }
    }

    private func needsCapture(_ window: WindowEntry) -> Bool {
        guard let existing = memory.value(for: window.thumbKey.hex) else {
            // Nothing in memory: try disk before spending a cross-process capture.
            if let loaded = loadFromDisk(window.thumbKey) {
                memory.store(loaded, for: window.thumbKey.hex)
                return false
            }
            return true
        }
        // A minimized window's pixels cannot change, so a stale image is still correct.
        guard !window.flags.mayLackPixels else { return false }
        return Date().timeIntervalSince(existing.capturedAt) > freshness.seconds
    }

    private func captureAndStore(_ window: WindowEntry) async {
        defer { inFlight.remove(window.id) }
        guard let image = await capturer.capture(windowID: window.id, maxPixelWidth: maxPixelWidth)
        else { return }

        let thumbnail = ThumbnailImage(image: image)
        memory.store(thumbnail, for: window.thumbKey.hex)
        writeToDisk(image, key: window.thumbKey)
    }

    // MARK: - Disk

    /// Sharded by key prefix: a few thousand files in one directory makes every
    /// enumeration slow.
    private func fileURL(_ key: ThumbKey) -> URL {
        let hex = key.hex
        let shard = String(hex.prefix(2))
        let folder = directory.appending(path: shard)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(hex).jpg")
    }

    /// JPEG rather than HEIC: it decodes roughly four times faster, and decode latency
    /// is what the user feels when the overlay appears. Disk space is not the scarce
    /// resource here.
    private func writeToDisk(_ image: CGImage, key: ThumbKey) {
        let url = fileURL(key)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.72
        ] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private func loadFromDisk(_ key: ThumbKey) -> ThumbnailImage? {
        let url = fileURL(key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  // Forces the decode to happen here, off the main thread, rather than
                  // lazily during the render pass.
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelWidth,
              ] as CFDictionary)
        else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date.distantPast
        return ThumbnailImage(image: image, capturedAt: modified)
    }

    /// Trims the cache to its budget, oldest first. Run at launch, not on the hot path.
    func evictIfNeeded() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey]
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys
        )?.compactMap({ $0 as? URL }) else { return }

        let sized = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileSize else { return nil }
            return (url, size, values.contentAccessDate ?? .distantPast)
        }
        var total = sized.reduce(0) { $0 + $1.1 }
        guard total > diskBudget else { return }

        for (url, size, _) in sized.sorted(by: { $0.2 < $1.2 }) {
            guard total > diskBudget else { break }
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}

/// Deliberately a lock rather than an actor: the overlay reads dozens of entries
/// synchronously while assembling a frame, and an actor would force every one of those
/// reads to suspend.
final class MemoryTier: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: ThumbnailImage] = [:]
    private var order: [String] = []
    private let capacity: Int

    init(capacity: Int = 240) {
        self.capacity = capacity
    }

    func value(for key: String) -> ThumbnailImage? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func store(_ image: ThumbnailImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if entries[key] == nil { order.append(key) }
        entries[key] = image
        while order.count > capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
    }
}

extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
