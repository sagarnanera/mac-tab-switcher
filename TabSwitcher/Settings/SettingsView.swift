import AppKit
import SwiftUI
import SwitcherCore

/// Settings, split into panes behind a sidebar.
///
/// One long form worked while there were four options and stopped working at ten:
/// unrelated settings sat next to each other and the thing you wanted was never where
/// you looked. Panes group by *what you are trying to change*, which is also how macOS
/// System Settings has worked since Ventura — a switcher should not invent its own
/// idiom for something this ordinary.
struct SettingsView: View {
    @Bindable var preferences: Preferences
    /// Passed in rather than reached for globally so a settings window can be rendered in
    /// a preview or a demo without starting a real updater.
    let updates: UpdateController
    let onChange: () -> Void

    @State private var pane: Pane? = .general

    enum Pane: String, CaseIterable, Identifiable {
        case general, shortcut, appearance, permissions

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .shortcut: "Shortcut"
            case .appearance: "Appearance"
            case .permissions: "Permissions"
            }
        }

        /// SF Symbols rather than emoji: they inherit weight and colour, and stay
        /// legible at every size.
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .shortcut: "keyboard"
            case .appearance: "square.grid.2x2"
            case .permissions: "lock.shield"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 172, max: 200)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane(preferences: preferences, updates: updates)
                case .shortcut: ShortcutPane(preferences: preferences)
                case .appearance: AppearancePane(preferences: preferences)
                case .permissions: PermissionsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(pane?.title ?? "Settings")
        }
        .frame(width: 720, height: 460)
        .onChange(of: preferences.tileWidth) { _, _ in onChange() }
        .onChange(of: preferences.dwellMode) { _, _ in onChange() }
        .onChange(of: preferences.dwellMilliseconds) { _, _ in onChange() }
        .onChange(of: preferences.breakOutNativeTabs) { _, _ in onChange() }
        .onChange(of: preferences.includeMinimized) { _, _ in onChange() }
        .onChange(of: preferences.bestQualityThumbnails) { _, _ in onChange() }
        .onChange(of: preferences.hotkey) { _, _ in onChange() }
        .onChange(of: preferences.showsKeyboardHints) { _, _ in onChange() }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var preferences: Preferences
    let updates: UpdateController
    @State private var confirmingReset = false
    /// Mirrors Sparkle's own setting rather than duplicating it into `Preferences`:
    /// Sparkle owns this value, writes it itself when it asks on second launch, and two
    /// stores for one switch is how they end up disagreeing.
    @State private var checksAutomatically = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                if LaunchAtLogin.needsApproval {
                    Label(
                        "Waiting for approval in System Settings → General → Login Items",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
                if let error = preferences.launchAtLoginError {
                    Label(error, systemImage: "xmark.circle").foregroundStyle(.red).font(.callout)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $checksAutomatically)
                    .onChange(of: checksAutomatically) { _, value in
                        updates.checksAutomatically = value
                    }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if let last = updates.lastCheck {
                            Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                                .settingsHelp()
                        } else {
                            Text("Not checked yet").settingsHelp()
                        }
                    }
                    Spacer()
                    Button("Check Now") { updates.checkForUpdates() }
                        .disabled(!updates.canCheck)
                }
                // Said here because it is not obvious and it matters: this app is not
                // notarized, so Apple has vouched for nothing. The signature on an update
                // is the only thing that does.
                Text("Updates are verified against a signing key built into this app. "
                     + "They are downloaded from the project's GitHub releases.")
                    .settingsHelp()
            }
            .onAppear { checksAutomatically = updates.checksAutomatically }

            Section("What counts as a window") {
                Toggle("List Finder and Terminal tabs separately", isOn: $preferences.breakOutNativeTabs)
                // Helper text explains the consequence rather than restating the label.
                Text("Off, a Finder window with six tabs appears once instead of six times.")
                    .settingsHelp()

                Toggle("Include minimized windows", isOn: $preferences.includeMinimized)
                Text("Minimized windows still show a preview of how they last looked.")
                    .settingsHelp()
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Restore defaults")
                        Text("Returns every setting to how it shipped. Login item is left alone.")
                            .settingsHelp()
                    }
                    Spacer()
                    Button("Restore") { confirmingReset = true }
                        .disabled(!preferences.hasChangesFromDefaults)
                }
            }
            // Destructive-ish and irreversible, so it confirms first and names exactly
            // what it will and will not touch.
            .confirmationDialog(
                "Restore all settings to their defaults?",
                isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button("Restore defaults", role: .destructive) { preferences.restoreDefaults() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your shortcut, dwell timing and appearance return to how they shipped. "
                     + "Launch at login is not changed.")
            }

            // Quitting sits apart from everything else: it is the one action here that
            // is not a preference.
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TabSwitcher runs in the menu bar")
                        Text("It has no Dock icon, so quit it from here or the menu bar icon.")
                            .settingsHelp()
                    }
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcut

private struct ShortcutPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Summon") {
                LabeledContent("Shortcut") {
                    HotkeyRecorder(hotkey: $preferences.hotkey)
                }
                Text("Hold the modifier and tap the key to move through apps. Release to switch.")
                    .settingsHelp()
            }

            Section("Seeing an app's windows") {
                Picker("Reveal windows", selection: $preferences.dwellMode) {
                    Text("When I pause on an app").tag("delayed")
                    Text("Immediately").tag("instant")
                    Text("Only when I press ↓").tag("manual")
                }
                .pickerStyle(.inline)

                if preferences.dwellMode == "delayed" {
                    LabeledContent("Pause for") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(preferences.dwellMilliseconds) },
                                    set: { preferences.dwellMilliseconds = Int($0) }
                                ),
                                in: 150...2000, step: 50
                            )
                            .frame(width: 200)
                            Text("\(preferences.dwellMilliseconds) ms")
                                .monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }

                Text(
                    "Tap the shortcut quickly and you move through apps. "
                    + "Pause on an app with several windows and they appear below it — "
                    + "the same key then steps through those windows before moving on."
                )
                .settingsHelp()
            }

            Section("While the overlay is open") {
                shortcutRow("⌥1 – ⌥9", "Jump straight to that window")
                shortcutRow("↓ ↑", "Step into an app's windows, or back out")
                shortcutRow("← →", "Move within the windows")
                shortcutRow("Type anything", "Search every window by name")
                shortcutRow("esc", "Cancel without switching")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ keys: String, _ meaning: String) -> some View {
        LabeledContent {
            Text(meaning).foregroundStyle(.secondary)
        } label: {
            Text(keys).monospaced()
        }
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Preview size") {
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $preferences.tileWidth, in: 120...400, step: 10)
                            .frame(width: 200)
                        Text("\(Int(preferences.tileWidth)) pt")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                // A number in points means nothing on its own; showing the proportion
                // at the chosen size makes the setting self-explanatory.
                previewSample
                Text("Previews shrink to fit the screen, then wrap onto more rows.")
                    .settingsHelp()
            }

            Section("Overlay") {
                Toggle("Show key hints", isOn: $preferences.showsKeyboardHints)
                Text("The reminders along the bottom of the switcher. Worth turning off "
                     + "once the keys are familiar.")
                    .settingsHelp()
            }

            Section("Quality") {
                Toggle("Full-resolution previews", isOn: $preferences.bestQualityThumbnails)
                Text("Sharper on Retina displays, and roughly four times the memory per preview.")
                    .settingsHelp()
            }
        }
        .formStyle(.grouped)
    }

    private var previewSample: some View {
        let width = preferences.tileWidth / 2
        return HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(index == 1 ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(index == 1 ? Color.accentColor : .clear, lineWidth: 2)
                    )
                    .frame(width: width, height: width / 1.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.15), value: preferences.tileWidth)
        .accessibilityHidden(true)
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @State private var accessibility = AXPermission.isTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var copied = false

    /// No notification exists for a TCC grant, so the pane polls while it is open.
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Accessibility",
                    granted: accessibility,
                    cost: "Without it, minimized state and Finder tabs are not detected.",
                    pane: "Privacy_Accessibility"
                )
                permissionRow(
                    title: "Screen Recording",
                    granted: screenRecording,
                    cost: "Without it, tiles show app icons instead of previews.",
                    pane: "Privacy_ScreenCapture"
                )
            } footer: {
                Text("TabSwitcher works without either — each one only adds detail.")
                    .settingsHelp()
            }

            Section("Troubleshooting") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Diagnostics")
                        Text("Permissions and which system features resolved on this Mac.")
                            .settingsHelp()
                    }
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Diagnostics.report(), forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                }
                if SecureInput.isEnabled {
                    Label(
                        "Secure input is active, so typing to search is unavailable until "
                        + "the app holding it (often a password field) gives it up.",
                        systemImage: "exclamationmark.lock"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            accessibility = AXPermission.isTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }

    private func permissionRow(title: String, granted: Bool, cost: String, pane: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            // Status is carried by an icon and a word, never by colour alone.
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(granted ? "Granted" : cost).settingsHelp()
                }
            } icon: {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
                    .accessibilityLabel(granted ? "Granted" : "Not granted")
            }
            Spacer()
            if !granted {
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
            }
        }
    }
}

// MARK: - Shared

private extension Text {
    /// Secondary, smaller, and never the only way a fact is communicated.
    func settingsHelp() -> some View {
        font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
