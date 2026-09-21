import AppKit
import SwitcherCore

/// Composition root. Everything is constructed here exactly once and wired together;
/// nothing else in the app reaches for a singleton.
@MainActor
final class AppEnvironment {
    let preferences: Preferences
    let store: WindowStore
    let thumbnails: ThumbnailStore
    let model: OverlayModel
    let activator: WindowActivator
    let hotkeys: HotkeyMonitor
    let controller: OverlayController
    private let observers: WindowObservers

    init() {
        preferences = Preferences()
        store = WindowStore()
        thumbnails = ThumbnailStore()
        model = OverlayModel(thumbnails: thumbnails)
        activator = WindowActivator(store: store)
        hotkeys = HotkeyMonitor()
        controller = OverlayController(
            model: model, store: store, thumbnails: thumbnails,
            activator: activator, hotkeys: hotkeys
        )
        observers = WindowObservers(store: store)
    }

    var hotkeyDescription: String { HotkeyRecorder.describe(preferences.hotkey) }
    var modifierDescription: String { HotkeyRecorder.describeModifiers(preferences.hotkey) }

    func start() {
        applyPreferences()
        controller.start()
        observers.start()

        let controller = controller
        Task {
            await store.setUpdateHandler { snapshot in
                controller.apply(snapshot: snapshot)
            }
            await store.refresh()
            await thumbnails.evictIfNeeded()
            await seedThumbnails()
        }
        Diagnostics.log("private API availability:\n\(Diagnostics.capabilityReport())")
    }

    /// Captures each app's frontmost window shortly after launch, so the first summon
    /// shows previews instead of a grid of icons that fill in afterwards.
    ///
    /// Cheap — one capture per app, not per window — and it happens while the user is
    /// doing something else. Windows in the strip stay lazy: they are only worth
    /// capturing once an app is actually expanded.
    private func seedThumbnails() async {
        let snapshot = await store.current
        await thumbnails.warm(snapshot.groups.map(\.frontmost))
        model.thumbnailGeneration &+= 1
    }

    /// Called at launch and whenever a setting changes. Grouping options live in the
    /// store because they change what a snapshot *is*, not merely how it is drawn.
    func applyPreferences() {
        model.metrics = preferences.tileMetrics
        model.showsKeyboardHints = preferences.showsKeyboardHints
        controller.setDwellPolicy(preferences.dwellPolicy)
        hotkeys.setHotkey(preferences.hotkey)
        let options = preferences.groupingOptions
        Task {
            await store.setGroupingOptions(options)
            await store.refresh()
        }
    }
}
