import SwiftUI
import SwitcherCore

/// The switcher itself: an app row that reveals a window strip beneath it.
struct OverlayView: View {
    @Bindable var model: OverlayModel

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
        .fixedSize()
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
            }
        }
    }

    /// The reveal is startling the first few times unless something signals it is
    /// coming. This bar is how the gesture is taught.
    private func dwellBar(visible: Bool) -> some View {
        Capsule()
            .fill(.tertiary)
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
                        windowCount: nil
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: layout.tileSize.height + 30)
        .padding(.top, 12)
        .transition(.opacity)
    }

    // MARK: - Filtering

    private var filterResults: some View {
        let layout = TileSizing.layout(
            count: min(state.results.count, 8), screen: screenSize, metrics: stripMetrics
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(state.filter).font(.title3)
            }
            if state.results.isEmpty {
                Text("No windows match").foregroundStyle(.secondary).padding(.vertical, 20)
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
                                    .foregroundStyle(.tertiary)
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

    private var footer: some View {
        HStack(spacing: 14) {
            if model.secureInputWarning {
                Label("Secure input active — typing to filter is unavailable", systemImage: "exclamationmark.lock")
                    .foregroundStyle(.orange)
            } else {
                hint
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 14)
    }

    private var hint: some View {
        Group {
            switch state.selection {
            case .flat:
                Text("↵ switch · esc cancel")
            case .grouped(_, let window) where window != nil:
                Text("↑ back to apps · ←→ windows · release to switch")
            case .grouped:
                if state.showsStrip {
                    Text("↓ pick a window · ⇥ next app")
                } else if state.selectedApp?.isExpandable == true {
                    Text("hold to see windows · ↓ now · ⇥ next app")
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
