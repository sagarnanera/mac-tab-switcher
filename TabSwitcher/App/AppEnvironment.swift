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
        }
        Diagnostics.log("private API availability:\n\(Diagnostics.capabilityReport())")
    }

    /// Called at launch and whenever a setting changes. Grouping options live in the
    /// store because they change what a snapshot *is*, not merely how it is drawn.
    func applyPreferences() {
        model.metrics = preferences.tileMetrics
        controller.setDwellPolicy(preferences.dwellPolicy)
        let options = preferences.groupingOptions
        Task {
            await store.setGroupingOptions(options)
            await store.refresh()
        }
    }
}
