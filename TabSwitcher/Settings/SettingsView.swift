import AppKit
import SwiftUI
import SwitcherCore

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let onChange: () -> Void

    var body: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Summon")
                    Spacer()
                    HotkeyRecorder(hotkey: $preferences.hotkey)
                }
                Text("Hold the modifier and tap the key to cycle; release to switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)
                if LaunchAtLogin.needsApproval {
                    Text("Waiting for approval in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = preferences.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Appearance") {
                VStack(alignment: .leading) {
                    Slider(value: $preferences.tileWidth, in: 120...400, step: 10) {
                        Text("Preview size")
                    } minimumValueLabel: {
                        Text("120").font(.caption2)
                    } maximumValueLabel: {
                        Text("400").font(.caption2)
                    }
                    Text("\(Int(preferences.tileWidth)) pt — previews shrink to fit the screen, then wrap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Revealing windows") {
                Picker("When to show an app's windows", selection: $preferences.dwellMode) {
                    Text("After resting on it").tag("delayed")
                    Text("Immediately").tag("instant")
                    Text("Only when I press ↓").tag("manual")
                }
                .pickerStyle(.radioGroup)

                if preferences.dwellMode == "delayed" {
                    VStack(alignment: .leading) {
                        Slider(
                            value: Binding(
                                get: { Double(preferences.dwellMilliseconds) },
                                set: { preferences.dwellMilliseconds = Int($0) }
                            ),
                            in: 150...2000, step: 50
                        )
                        Text("\(preferences.dwellMilliseconds) ms. Pressing ↓ always works immediately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                HStack {
                    Text("TabSwitcher runs in the menu bar with no Dock icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // A second way out. The menu bar item can be unreachable on a
                    // crowded or notched display, and an agent app has no Dock icon to
                    // fall back on.
                    Button("Quit TabSwitcher") { NSApplication.shared.terminate(nil) }
                }
            }

            Section("What counts as a window") {
                Toggle("Show tabs of Finder, Terminal and Preview separately", isOn: $preferences.breakOutNativeTabs)
                Toggle("Include minimized windows", isOn: $preferences.includeMinimized)
                Toggle("Full-resolution previews", isOn: $preferences.bestQualityThumbnails)
                Text("Full resolution is sharper on Retina displays and costs more memory per preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: preferences.tileWidth) { _, _ in onChange() }
        .onChange(of: preferences.dwellMode) { _, _ in onChange() }
        .onChange(of: preferences.dwellMilliseconds) { _, _ in onChange() }
        .onChange(of: preferences.breakOutNativeTabs) { _, _ in onChange() }
        .onChange(of: preferences.includeMinimized) { _, _ in onChange() }
        .onChange(of: preferences.bestQualityThumbnails) { _, _ in onChange() }
        .onChange(of: preferences.hotkey) { _, _ in onChange() }
    }
}
