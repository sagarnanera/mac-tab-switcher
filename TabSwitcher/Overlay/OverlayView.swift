import SwiftUI
import SwitcherCore

/// The switcher itself: an app row that reveals a window strip beneath it.
struct OverlayView: View {
    @Bindable var model: OverlayModel
    /// Mouse events go through the same inputs the keyboard uses, so hover and click
    /// cannot drift out of step with the state machine's rules.
    let onInput: (OverlayInput) -> Void

    /// Normally nil; `--demo-a11y` supplies one so the accessibility branches can be
    /// inspected without changing the machine's own settings. Stored on the view rather
    /// than injected around it, because the hosting controller is generic over this
    /// exact type and widening it to `some View` costs more than it buys.
    var appearanceOverride: OverlayAppearance? = OverlayAppearance.fromCommandLine()

    @Environment(\.overlayAppearance) private var systemAppearance

    private var appearance: OverlayAppearance { appearanceOverride ?? systemAppearance }

    private var state: OverlayState { model.state }

    var body: some View {
        VStack(spacing: 0) {
            if state.isFiltering {
                filterResults
            } else {
                appRow
                if state.showsStrip, let app = state.selectedApp {
                    Divider().padding(.horizontal, 20)
                    windowStrip(for: app)
                }
            }
            footer
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(appearance.panelBorder, lineWidth: appearance.panelBorderWidth)
        )
        .fixedSize()
        .animation(appearance.stripReveal, value: state.showsStrip)
        .environment(\.overlayAppearanceOverride, appearanceOverride)
    }

    // MARK: - App row

    private var appRow: some View {
        let layout = TileSizing.layout(
            count: state.groups.count, screen: screenSize, metrics: model.metrics
        )
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(layout.tileSize.width), spacing: 12),
                           count: max(1, layout.columns)),
            spacing: 14
        ) {
            ForEach(Array(state.groups.enumerated()), id: \.element.id) { index, group in
                VStack(spacing: 4) {
                    TileView(
                        window: group.frontmost,
                        app: group.app,
                        image: model.thumbnail(for: group.frontmost),
                        icon: model.icon(for: group.app),
                        size: layout.tileSize,
                        isSelected: isAppSelected(index),
                        windowCount: group.windows.count
                    )
                    dwellBar(visible: isAppSelected(index) && model.showsDwellProgress)
                        .frame(width: layout.tileSize.width)
                }
                .contentShape(.rect)
                .onHover { inside in
                    // Hovering arms dwell exactly as keyboard selection does, so
                    // resting the pointer on an app reveals its windows too.
                    if inside { onInput(.hover(app: index, window: nil)) }
                }
                .onTapGesture { onInput(.confirm) }
            }
        }
    }

    /// The reveal is startling the first few times unless something signals it is
    /// coming. This bar is how the gesture is taught.
    private func dwellBar(visible: Bool) -> some View {
        Capsule()
            .fill(appearance.dwellTrack)
            .frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * model.dwellProgress)
                }
            }
            .opacity(visible ? 1 : 0)
    }

    // MARK: - Window strip

    private func windowStrip(for group: AppGroup) -> some View {
        // Strip tiles are smaller than app tiles so the hierarchy reads at a glance:
        // the row you navigate with Tab stays visually dominant.
        let layout = TileSizing.layout(
            count: group.windows.count,
            screen: screenSize,
            metrics: stripMetrics
        )
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                    TileView(
                        window: window,
                        app: group.app,
                        image: model.thumbnail(for: window),
                        icon: model.icon(for: group.app),
                        size: layout.tileSize,
                        isSelected: isWindowSelected(index),
                        windowCount: nil,
                        shortcutDigit: index < 9 ? index + 1 : nil
                    )
                    .contentShape(.rect)
                    .onHover { inside in
                        if inside { onInput(.hover(app: currentAppIndex, window: index)) }
                    }
                    .onTapGesture { onInput(.confirm) }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: layout.tileSize.height + 30)
        .padding(.top, 12)
        .transition(appearance.stripTransition)
    }

    // MARK: - Filtering

    private var filterResults: some View {
        let layout = TileSizing.layout(
            count: min(state.results.count, 8), screen: screenSize, metrics: stripMetrics
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(appearance.secondaryText)
                Text(state.filter).font(.title3)
            }
            if state.results.isEmpty {
                Text("No windows match").foregroundStyle(appearance.secondaryText).padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(state.results.prefix(24).enumerated()), id: \.element.window.id) { index, result in
                            VStack(spacing: 2) {
                                TileView(
                                    window: result.window,
                                    app: result.app,
                                    image: model.thumbnail(for: result.window),
                                    icon: model.icon(for: result.app),
                                    size: layout.tileSize,
                                    isSelected: isFlatSelected(index),
                                    windowCount: nil
                                )
                                Text(result.app.name)
                                    .font(.caption2)
                                    .foregroundStyle(appearance.tertiaryText)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: layout.tileSize.height + 44)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if model.secureInputWarning {
            // Always shown, even with hints turned off: this explains why typing has
            // stopped working, and without it the overlay just looks broken.
            Label("Secure input active — typing to filter is unavailable",
                  systemImage: "exclamationmark.lock")
                .font(.caption2)
                .foregroundStyle(appearance.warningText)
                .padding(.top, 14)
        } else if model.showsKeyboardHints {
            hint
                .font(.caption2)
                .foregroundStyle(appearance.secondaryText)
                .padding(.top, 14)
        }
    }

    private var hint: some View {
        Group {
            switch state.selection {
            case .flat:
                Text("↵ switch · esc cancel")
            case .grouped(_, let window) where window != nil:
                Text("⇥ next window · ⌥1-9 jump · ↑ back to apps · release to switch")
            case .grouped:
                if state.showsStrip {
                    Text("⇥ steps into these windows · ⌥1-9 jump · release to switch")
                } else if state.selectedApp?.isExpandable == true {
                    Text("⇥ next app · pause to see this app's windows")
                } else {
                    Text("⇥ next app · type to search")
                }
            }
        }
    }

    // MARK: - Helpers

    private var stripMetrics: TileSizing.Metrics {
        var metrics = model.metrics
        metrics.preferredWidth = max(metrics.minimumWidth, metrics.preferredWidth * 0.8)
        return metrics
    }

    private var currentAppIndex: Int {
        if case .grouped(let app, _) = state.selection { return app }
        return 0
    }

    private var screenSize: CGSize {
        NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
    }

    private func isAppSelected(_ index: Int) -> Bool {
        if case .grouped(let app, let window) = state.selection { return app == index && window == nil }
        return false
    }

    private func isWindowSelected(_ index: Int) -> Bool {
        if case .grouped(_, let window) = state.selection { return window == index }
        return false
    }

    private func isFlatSelected(_ index: Int) -> Bool {
        if case .flat(let selected) = state.selection { return selected == index }
        return false
    }
}
