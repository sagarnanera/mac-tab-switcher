import SwiftUI
import SwitcherCore

/// One window preview: thumbnail, app icon, title, state badges.
struct TileView: View {
    let window: WindowEntry
    let app: AppRef
    let image: CGImage?
    let icon: NSImage?
    let size: CGSize
    let isSelected: Bool
    /// Shown on app-row tiles when the app has more than one window.
    let windowCount: Int?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    placeholder
                }
                badges
            }
            .frame(width: size.width, height: size.height)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            Text(window.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: size.width)
        }
    }

    /// A window with no capturable pixels still needs to be recognisable, so the
    /// fallback is the app icon rather than an empty box.
    private var placeholder: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.height * 0.45)
                    .opacity(0.8)
            }
        }
    }

    private var badges: some View {
        VStack {
            HStack {
                if let icon, image != nil {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Spacer()
                if let windowCount, windowCount > 1 {
                    Label("\(windowCount)", systemImage: "square.on.square")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            Spacer()
            HStack {
                Spacer()
                ForEach(stateBadges, id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.caption2)
                        .padding(3)
                        .background(.thinMaterial, in: Circle())
                }
            }
        }
        .padding(5)
    }

    private var stateBadges: [String] {
        var symbols: [String] = []
        if window.flags.contains(.minimized) { symbols.append("arrow.down.right.and.arrow.up.left") }
        if window.flags.contains(.otherSpace) { symbols.append("rectangle.on.rectangle") }
        if window.flags.contains(.fullScreen) { symbols.append("arrow.up.left.and.arrow.down.right") }
        return symbols
    }
}
