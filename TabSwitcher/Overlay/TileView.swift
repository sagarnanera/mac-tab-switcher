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
    /// Shown on strip tiles: the digit that jumps straight here. Makes the shortcut
    /// discoverable instead of hidden, which is the difference between a power feature
    /// and a secret.
    var shortcutDigit: Int? = nil
    /// Position within its row, for the spoken label. SwiftUI's own traversal order
    /// does not match the order the cycle key moves through, so it cannot be inferred.
    var position: (index: Int, total: Int)? = nil

    @Environment(\.overlayAppearance) private var appearance

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
            .overlay(selectionRing)

            Text(window.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : appearance.secondaryText)
                .frame(width: size.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(narration)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Falls back to a bare position of 1-of-1 when the caller did not supply one, which
    /// suppresses the positional clause rather than inventing a wrong one.
    private var narration: String {
        TileNarration.label(
            window: window,
            app: app,
            index: position?.index ?? 0,
            total: position?.total ?? 1,
            windowCount: windowCount
        )
    }

    /// Two concentric rings, not one.
    ///
    /// The ring is drawn straight onto a window screenshot, which can be any colour at
    /// all — a plain accent-coloured border disappears against a blue window for
    /// everyone, not only against a colour-vision deficiency. The halo underneath is
    /// near-black in dark appearance and near-white in light, so whichever of the two
    /// rings loses contrast, the other one holds the edge.
    @ViewBuilder
    private var selectionRing: some View {
        if isSelected {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(appearance.selectionHalo,
                                  lineWidth: appearance.selectionOuterWidth)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: appearance.selectionInnerWidth)
            }
        } else if appearance.unselectedBorderOpacity > 0 {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.primary.opacity(appearance.unselectedBorderOpacity), lineWidth: 1)
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
                if let shortcutDigit {
                    Text("\(shortcutDigit)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel("Option \(shortcutDigit) to switch here")
                }
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
