import SwiftUI

struct WelcomeView: View {
    @Bindable var model: WelcomeModel
    let onFinish: () -> Void

    /// No notification exists for a TCC grant, and the user leaves the app to give one,
    /// so the window watches for their return.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 44)
                .padding(.vertical, 32)
            footer
        }
        .frame(width: 560, height: 470)
        .onReceive(poll) { _ in model.refreshPermissions() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: welcome
        case .permissions: permissions
        case .gesture: gesture
        case .tryIt: tryIt
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            // Read from the asset catalog rather than NSApp.applicationIconImage, which
            // goes through the LaunchServices icon cache and can serve a stale icon for
            // a long time after the app is rebuilt.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)
            Text(model.step.title).font(.largeTitle.weight(.semibold))
            Text("⌘Tab switches between apps. TabSwitcher switches between **windows** — with a preview of each, so you can see where you are going.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 20) {
            header(model.step.title,
                   "Neither is required. Each one only adds detail, and you can change "
                   + "your mind later in Settings.")

            permissionRow(
                title: "Accessibility",
                granted: model.accessibility,
                purpose: "Lets TabSwitcher see window titles and bring a window forward.",
                cost: "Without it, minimized state and Finder tabs go undetected.",
                action: model.requestAccessibility
            )
            permissionRow(
                title: "Screen Recording",
                granted: model.screenRecording,
                purpose: "Lets TabSwitcher show a picture of each window.",
                cost: "Without it, you get app icons instead of previews.",
                action: model.requestScreenRecording
            )
        }
    }

    private var gesture: some View {
        VStack(spacing: 18) {
            header(model.step.title,
                   "Hold \(model.modifierDescription) and tap. The list expands when you "
                   + "slow down.", centered: true)
            GestureDemo()
        }
    }

    private var tryIt: some View {
        VStack(spacing: 20) {
            header(model.step.title, nil, centered: true)
            Text(model.hotkeyDescription)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if model.sawOverlay {
                Label("That's it — you're set up", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    // Announced rather than only shown, so the confirmation is not
                    // visual-only.
                    .accessibilityAddTraits(.updatesFrequently)
            } else {
                Text("Hold the modifier and tap the key. This window will confirm when "
                     + "the switcher appears.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pieces

    private func header(_ title: String, _ subtitle: String?, centered: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(title).font(.title.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    private func permissionRow(
        title: String, granted: Bool, purpose: String, cost: String, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon plus wording: status is never carried by colour alone.
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
                .accessibilityLabel(granted ? "Granted" : "Not granted")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(purpose).font(.callout).foregroundStyle(.secondary)
                if !granted {
                    Text(cost).font(.callout).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if granted {
                Text("Granted").foregroundStyle(.secondary).font(.callout)
            } else {
                Button("Grant", action: action)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            if !model.isFirstStep {
                Button("Back") { model.goBack() }
            }
            Spacer()
            // A step indicator, so the flow has a visible length rather than feeling
            // open-ended.
            HStack(spacing: 6) {
                ForEach(WelcomeModel.Step.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == model.step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityLabel("Step \(model.step.rawValue + 1) of \(WelcomeModel.Step.allCases.count)")
            Spacer()
            // Skip is always available: none of this is required for the app to work,
            // so trapping someone in it would be wrong.
            if model.isLastStep {
                Button("Done", action: onFinish).keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { model.advance() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
        .overlay(alignment: .topLeading) {
            if !model.isLastStep {
                Button("Skip", action: onFinish)
                    .buttonStyle(.link)
                    .padding(.leading, 24)
                    .padding(.top, 19)
                    .opacity(model.isFirstStep ? 1 : 0)
            }
        }
    }
}
