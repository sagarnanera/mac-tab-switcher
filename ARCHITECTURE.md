# TabSwitcher — architecture

Written for whoever (or whatever) picks this codebase up next, so the same ground does
not have to be re-derived from the source every time. It records the shape of the
system, the rules that must not be broken, the decisions that look arbitrary but are
not, and the macOS traps that each cost a real debugging session.

If you change something here, update this file in the same commit.

---

## 1. What the app is

A menu-bar agent. `⌥Tab` opens a borderless overlay showing one tile per **application**,
each with a live preview of its frontmost window. Pause on an app that has several
windows and a strip of those windows expands beneath it; the same key then steps through
them before continuing to the next app. Release the modifier to switch.

It is a *window* switcher, not a tab switcher, despite the name. Browser-tab switching
was researched and deliberately deferred — see §8.

---

## 2. The map

```
Packages/SwitcherCore/          Pure logic. No AppKit, no Accessibility, no capture.
  Model/                        WindowEntry, AppGroup, AppRef, ThumbKey
  Kernels/                      One decision each, with a *Specs.md beside it
TabSwitcher/
  App/                          Entry point, composition root, preferences, diagnostics
  Platform/                     The ONLY place private macOS APIs are touched
  Inventory/                    Window discovery, and the store that keeps it warm
  Capture/                      Thumbnails: two backends, memory + disk tiers
  Input/                        Event tap on its own thread, hotkey matching
  Overlay/                      NSPanel + SwiftUI, driven by the state machine
  Focus/                        Raising one specific window of one specific app
  Settings/  Welcome/           SwiftUI windows
```

Where to look for a given task:

| Task | File |
|---|---|
| Change what the cycle key does | `Kernels/OverlayStateMachine.swift` |
| Change when windows are revealed | `Kernels/DwellPolicy.swift` |
| Change how the overlay looks under an Accessibility setting | `Kernels/AppearanceRules.swift`, never the views |
| Change what a screen reader says | `Kernels/TileNarration.swift` |
| A window is missing from the list | `Inventory/WindowFilter.swift`, then `WindowDiscovery.swift` |
| A window is listed that should not be | `Inventory/CGWindowCandidate.swift` (layer/alpha/size gate) |
| Previews missing or wrong | `Capture/WindowCapturer.swift`, `ThumbnailStore.swift` |
| Switching lands on the wrong window | `Focus/WindowActivator.swift` |
| Keys not reaching the app | `Input/HotkeyMonitor.swift` |
| Overlay does not update | `Overlay/OverlayController.swift` — see the `_modify` trap in §7 |
| Anything involving a private symbol | `Platform/PrivateAPI.swift`, and nowhere else |

---

## 3. Invariants

These are enforced by CI or by review. Breaking one does not usually fail the build; it
fails later and confusingly.

**`SwitcherCore` imports no OS framework.** Not AppKit, Cocoa, SwiftUI,
ApplicationServices, ScreenCaptureKit or Carbon. This is what lets 61 tests run in CI
with no GUI session, no permissions and no Xcode. CI greps for it.

**Private symbols are called only from `Platform/PrivateAPI.swift`.** Every one is
resolved with `dlsym`, never `@_silgen_name`, and every call site has a public fallback.
CI greps for this too, ignoring comments — other files are expected to *mention* these
symbols when explaining why a fallback exists.

**Nothing is looked up while the user is pressing the key.** Discovery runs at launch
and on system notifications; the hotkey path reads memory only. No Accessibility call,
no `SCShareableContent`, no disk read, no `await`. This — not the UI framework — is what
makes the overlay feel instant, and it is why SwiftUI is fast enough here.

**Accessibility calls never run on the main thread.** Each is a synchronous round-trip
serviced on the *target's* main thread; one hung app would otherwise freeze the switcher.

**Every decision worth testing is a pure function.** If logic is being added to a view or
a controller, it probably belongs in a kernel.

---

## 4. How a keypress becomes a switched window

```
CGEvent tap (own thread)
  └─ HotkeyMonitor matches the chord, consumes the key
       └─ OverlayController.dispatch(input)          [main actor]
            ├─ OverlayState.apply(input) -> [Effect]  [pure]
            └─ performs each effect:
                 .show / .hide          -> NSPanel
                 .armDwell              -> timer; expiry re-enters as .dwellElapsed
                 .wantThumbnails        -> ThumbnailStore.warm
                 .activate(window)      -> WindowActivator
```

Meanwhile, continuously and off the hot path:

```
AX notifications + NSWorkspace notifications
  └─ WindowObservers  -> WindowStore.requestRefresh (debounced 150ms)
       └─ WindowDiscovery.run()
            ├─ CGWindowList        existence, id, geometry, layer, alpha
            ├─ Accessibility       titles, minimized/main, document URL, element
            ├─ Spaces (private)    which Space a window is on
            └─ NSWorkspace         app identity
       └─ AppGrouping.group(...) -> WindowSnapshot -> main actor -> OverlayController
```

The state machine is fed its own timer expiry as an input. That is what makes dwell
behaviour a unit test rather than a stopwatch and a pair of eyes.

---

## 5. Decisions that look arbitrary and are not

**Three sources are merged for discovery, because none is sufficient.** `CGWindowList`
knows what exists but not what it is called (without Screen Recording) and cannot raise
anything. Accessibility knows titles and can raise, but only ever describes the *current
Space*. The private Spaces calls say which Space a window is on. Removing any one loses
a category of window.

**`CGWindowListCopyWindowInfo`, not ScreenCaptureKit, for enumeration.** Faster, not
deprecated (only the *image* call was removed), and needs no Screen Recording grant for
geometry — so the switcher still works when previews do not.

**Private APIs are accepted for three things and no others**: pixels for minimized
windows, reaching windows on other Spaces, and raising one specific window of a
backgrounded app. No public API does any of these. Verified on this machine that
minimized capture genuinely works. See `docs/PRIVATE_APIS.md` for each symbol and its
fallback.

**`dlsym`, never `@_silgen_name`.** `@_silgen_name` links at build time, so a macOS
release that removes a symbol makes the app fail to *launch* — dyld kills it before
`main`. `dlsym` returns nil and the call site degrades.

**The model type is `WindowEntry`, not `WindowRef`.** Carbon exports a global `WindowRef`
that AppKit re-exports transitively; the collision is unresolvable at every use site.

**The memory thumbnail tier is a lock, not an actor.** The overlay reads dozens of
entries synchronously while assembling a frame; an actor would force every read to
suspend.

**`AppleScriptBridge`-style serial pinning** does not exist here, but the same reasoning
governs `AXQueue`: bounded concurrency (4), not unbounded, so thirty unresponsive apps
cannot spawn thirty blocked threads.

### Rules that were deliberately reversed

Recording these because the earlier reasoning is still persuasive, and an agent that
rediscovers it may "fix" the code back.

**"The cycle key must always mean *next app*."** Reversed. The original argument was that
a key whose meaning depends on invisible state cannot be pressed quickly. But the state
is *not* invisible — the meaning changes exactly when the window strip appears on
screen. The rule's real cost was that reaching a window required an arrow key, i.e. the
other hand leaving the modifier, which defeats the point of a switcher. Now: tap quickly
to skim apps; pause and the same key walks that app's windows before continuing on.
Walking off the end continues to the next app rather than wrapping, so nobody is trapped.

**"AppKit only; SwiftUI cannot hit the latency budget."** Reversed. AltTab needs 80-90ms
in pure AppKit, but it spends that time *gathering the window list while the key is
held*. The framework was never the bottleneck; doing work at the wrong moment was. With
the list kept warm, SwiftUI is comfortably fast enough.

**"Gate startup on Accessibility."** Reversed. The app is usable without it — titles come
from the Window Server and raising goes through the private front-process call — so
blocking launch traded a working switcher for a dialog.

---

## 6. Permissions, and why the app must survive without them

| | Granted | Denied |
|---|---|---|
| Screen Recording | previews, and window *titles* from the Window Server | app icons instead of previews |
| Accessibility | minimized/main state, native tab detection, reliable raise | still switches, via the private front-process call |

The two cover for each other: titles come from whichever is available. With **neither**,
windows are labelled by app name rather than dropped — an earlier version treated "no
title" as "not a real window", which with Screen Recording denied deleted every window
and left the switcher empty.

Going through private APIs does **not** avoid the Screen Recording grant. The gate is in
WindowServer, which owns the pixels, so the private capture call sits behind the same
check as ScreenCaptureKit. It buys minimized-window access, not freedom from permission.

---

## 7. macOS traps

Each of these cost real debugging time and none is discoverable from the code.

**TCC grants are keyed to the code signature.** An ad-hoc signature gets a fresh cdhash
every build, so the Accessibility toggle stays visibly ON while every call fails. The
fix is a stable identity (`Scripts/setup.sh`). Verify with
`codesign -d -r- <app> | grep designated` — it must be identity-based and identical
across two builds, not a cdhash.

**`@Observable` does not instrument `_modify`.** Calling a `mutating` method directly on
an observable's value-type property emits no change notification, so SwiftUI renders once
and then ignores everything. Read out, mutate the copy, assign back. This made the entire
overlay inert for a while and looked like a state-machine bug.

**`EXCLUDED_SOURCE_FILE_NAMES` excludes from every build phase**, not just compilation.
The app icon silently shipped missing while the build reported success.

**`actool` crashes on an unknown key in `icon.json`** — "attempt to insert nil object",
no useful message. Layers have no `fill` key; opacity belongs in the SVG.

**`NSApp.applicationIconImage` reads through the LaunchServices icon cache** and serves a
stale icon long after a rebuild. Read the asset catalog directly.

**An accessory app cannot bring a window to the front.** It has no Dock presence for
macOS to activate. Become `.regular` while a window is open and revert on close.

**Title-bar buttons must be hidden after the content view is installed** — doing it
earlier is undone when the titlebar accessory is rebuilt.

**macOS reports `loginwindow` as frontmost during a Space transition.** A raise that
crosses Spaces animates for several hundred milliseconds; a short verification window
reads that as failure and fires a second activation into the animation.

**Remote-token AX element ids are not clustered low.** Probing must cover the full range;
on this machine VS Code's windows sit at 1386, 1387, 1390, 3994 and 17201. An early
bail-out found nothing and every off-Space window ended up unraisable.

**`isOnScreen` from ScreenCaptureKit is unusable as a filter** — false even for plainly
visible frontmost windows.

**SwiftUI parses markdown only from string *literals*.** Concatenated strings render
their asterisks.

**Secure input filters `.keyDown` from every event tap system-wide, but not
`.flagsChanged`.** So modifier tracking keeps working while typing-to-search dies. The
overlay says so rather than appearing broken.

---

## 8. Deliberately not done

**Browser-tab switching.** A background tab has no capturable pixels by any mechanism —
not ScreenCaptureKit, not Accessibility, not even a browser extension
(`captureVisibleTab` is active-tab-only). The workable design is capture-on-tab-exit with
a URL-keyed cache and favicon fallbacks. AltTab's maintainer rejected a working
implementation of this outright as unmaintainable. The `WindowSource` boundary exists so
a tab source could be added without rearchitecting.

**Notarization.** Needs a paid Developer ID. Without it a browser download is blocked
outright (the Control-click bypass is gone) and Homebrew is closed, since casks have
required notarization since September 2026. A `curl | bash` installer *does* work — the
quarantine flag is set by the downloading application and `curl` does not set it — which
makes it the only viable install path while unsigned. See `docs/POLISH_PLAN.md`.

**Liquid Glass.** The overlay uses `.regularMaterial`, not `.glassEffect`. Measured on
macOS 27 in a real `.nonactivatingPanel` with our exact configuration: under Reduce
Transparency glass does *not* become opaque — it keeps tinting from whatever is behind
it, landing at `#2C1E21` where the material sits flat at `#393939`, and dropping
secondary caption text to 3.69:1 against the material's 5.65:1. Below the 4.5:1 floor,
and it varies with whichever window happens to be underneath. For a HUD that appears
over arbitrary content that is a contrast bug, not a style choice. Re-test before
adopting it; do not adopt it because a newer OS shipped.

**Localization.** Strings are hardcoded. Extracting to a String Catalog is planned.

---

## 9. Verifying a change

```bash
cd Packages/SwitcherCore && swift test     # 73 tests, no GUI needed
bash Scripts/build.sh                      # builds, signs, installs to ~/Applications
bash Scripts/build.sh --run
bash Scripts/quit.sh
```

Debug affordances, all on the built binary:

| Flag | Does |
|---|---|
| `--diagnose` | permissions, private-symbol availability, discovery timings, the grouped window list |
| `--diagnose --audit` | every surface the Window Server reports and why each was kept or dropped |
| `--demo` | summons the overlay without a keystroke — WindowServer refuses synthesised modifier keys, so it cannot be scripted |
| `--demo --demo-strip` | as above, then expands a window strip |
| `--demo-a11y=contrast,transparency,motion` | forces the Accessibility branches on, without touching the machine's own settings — every one of them is otherwise unreachable on a default Mac |
| `--settings <pane>` | opens Settings straight to `general`/`shortcut`/`appearance`/`permissions`; a script cannot click a sidebar row |
| `--test-login-item` | registers and unregisters the login item, writing the result to `/tmp/tabswitcher-loginitem.txt`. `SMAppService.mainApp` describes the calling bundle, so this is unreachable from a test binary |
| `--demo --demo-strip --dump-a11y` | walks the overlay's own accessibility tree to `/tmp/tabswitcher-a11y.txt` — what a screen reader would find, without switching VoiceOver on |
| `--test-activate` | activates every non-frontmost window of a multi-window app and reports whether focus landed |
| `--test-minimized` | minimizes a throwaway TextEdit window and proves pixels are still capturable |
| `--settings`, `--welcome-step N` | open those windows directly |

**`--diagnose` reports the permissions of whatever terminal launched it, not the app's.**
TCC attributes to the responsible process. For the app's own view, read
`/tmp/tabswitcher-status.txt`, which it writes on every launch.

---

## 10. Related documents

| Document | Contents |
|---|---|
| `docs/PRIVATE_APIS.md` | every private symbol, why, and what happens without it |
| `docs/PERMISSIONS.md` | permission matrix, signing, resetting grants |
| `docs/POLISH_PLAN.md` | remaining work toward a shippable app |
| `docs/WELCOME_PLAN.md` | reasoning behind the first-run flow |
| `Packages/SwitcherCore/**/[Name]Specs.md` | behaviour spec beside each kernel |
