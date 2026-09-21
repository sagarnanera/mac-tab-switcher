import SwiftUI

/// A looping illustration of the cycle key: tapping skims apps, pausing expands one.
///
/// Animated rather than described because the behaviour is the product's whole point
/// and a sentence about it reads as a footnote. Respects Reduce Motion by falling back
/// to a static before-and-after, which carries the same information without movement.
struct GestureDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private let apps = 4
    private let windows = 3
    /// Phases 0-2 skim; 3 pauses and expands; 4-5 walk the revealed windows.
    private let phaseCount = 6

    var body: some View {
        Group {
            if reduceMotion {
                staticComparison
            } else {
                animated
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Tapping the shortcut moves between apps. Pausing on an app reveals its "
            + "windows, and the same key then steps through them."
        )
    }

    private var animated: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(0..<apps, id: \.self) { index in
                    pane(selected: index == selectedApp && !isInWindows, width: 74, height: 50)
                }
            }
            if isExpanded {
                HStack(spacing: 8) {
                    ForEach(0..<windows, id: \.self) { index in
                        pane(selected: isInWindows && index == selectedWindow,
                             width: 58, height: 40)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .animation(nil, value: phase)
                .frame(height: 20)
        }
        .frame(height: 170, alignment: .top)
        .animation(.easeOut(duration: 0.28), value: phase)
        .task {
            while !Task.isCancelled {
                // The pause is held longer than the taps: that contrast is the whole
                // lesson, and matching their durations would hide it.
                try? await Task.sleep(for: .milliseconds(phase == 2 ? 1100 : 750))
                phase = (phase + 1) % phaseCount
            }
        }
    }

    private var staticComparison: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(0..<apps, id: \.self) { pane(selected: $0 == 1, width: 62, height: 42) }
                }
                Text("Tap to move between apps").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(0..<apps, id: \.self) { pane(selected: $0 == 1, width: 62, height: 42) }
                }
                HStack(spacing: 8) {
                    ForEach(0..<windows, id: \.self) { pane(selected: $0 == 0, width: 50, height: 34) }
                }
                Text("Pause on an app to reveal its windows").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func pane(selected: Bool, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.quaternary))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .frame(width: width, height: height)
    }

    private var selectedApp: Int { min(phase, 2) }
    private var isExpanded: Bool { phase >= 3 }
    private var isInWindows: Bool { phase >= 4 }
    private var selectedWindow: Int { phase - 4 }

    private var caption: String {
        switch phase {
        case 0, 1: "Tap — move between apps"
        case 2: "Pause here…"
        case 3: "…and its windows appear"
        default: "Keep tapping to step through them"
        }
    }
}
