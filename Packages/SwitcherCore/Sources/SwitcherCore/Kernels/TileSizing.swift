import CoreGraphics
import Foundation

/// Fits N tiles into the available width.
///
/// 400pt tiles were the original ask, but five of them is 2000pt and a 14" MacBook is
/// 1512pt wide. So the configured size is a *maximum*: tiles shrink toward a floor to
/// fit, and once the floor is reached they wrap to more rows rather than shrinking
/// into illegibility.
public enum TileSizing {

    public struct Layout: Sendable, Equatable {
        public let tileSize: CGSize
        public let columns: Int
        public let rows: Int

        public var contentSize: CGSize {
            CGSize(
                width: CGFloat(columns) * tileSize.width,
                height: CGFloat(rows) * tileSize.height
            )
        }
    }

    public struct Metrics: Sendable, Equatable {
        /// User's preferred tile width. Height follows from `aspectRatio`.
        public var preferredWidth: CGFloat
        /// Below this, a thumbnail stops being recognisable and the tile is just noise.
        public var minimumWidth: CGFloat
        public var aspectRatio: CGFloat
        public var gutter: CGFloat
        /// Fraction of the screen the overlay may occupy.
        public var maxScreenFraction: CGFloat

        public init(
            preferredWidth: CGFloat = 220,
            minimumWidth: CGFloat = 120,
            aspectRatio: CGFloat = 16.0 / 10.0,
            gutter: CGFloat = 12,
            maxScreenFraction: CGFloat = 0.8
        ) {
            self.preferredWidth = preferredWidth
            self.minimumWidth = minimumWidth
            self.aspectRatio = aspectRatio
            self.gutter = gutter
            self.maxScreenFraction = maxScreenFraction
        }

        public static let `default` = Metrics()

        public static func clampedWidth(_ width: CGFloat) -> CGFloat {
            min(400, max(120, width))
        }
    }

    public static func layout(count: Int, screen: CGSize, metrics: Metrics = .default) -> Layout {
        guard count > 0 else {
            return Layout(tileSize: .zero, columns: 0, rows: 0)
        }
        let available = max(metrics.minimumWidth, screen.width * metrics.maxScreenFraction)

        // How many preferred-width tiles fit on one row?
        let perRowAtPreferred = max(1, Int(available / (metrics.preferredWidth + metrics.gutter)))

        if count <= perRowAtPreferred {
            return Layout(
                tileSize: size(width: metrics.preferredWidth, metrics: metrics),
                columns: count,
                rows: 1
            )
        }

        // Try to keep one row by shrinking, but never past the floor.
        let shrunk = (available / CGFloat(count)) - metrics.gutter
        if shrunk >= metrics.minimumWidth {
            return Layout(tileSize: size(width: shrunk, metrics: metrics), columns: count, rows: 1)
        }

        // Floor reached: wrap. Columns are whatever fits at the floor width.
        let columns = max(1, Int(available / (metrics.minimumWidth + metrics.gutter)))
        let rows = Int(ceil(Double(count) / Double(columns)))
        return Layout(tileSize: size(width: metrics.minimumWidth, metrics: metrics), columns: columns, rows: rows)
    }

    private static func size(width: CGFloat, metrics: Metrics) -> CGSize {
        CGSize(width: width.rounded(), height: (width / metrics.aspectRatio).rounded())
    }
}
