# TabSwitcher

A macOS window switcher with previews and a two-level drill-down.

`Cmd+Tab` switches between *apps*. With two VS Code windows open you can reach the app
but not a specific window — you land on whichever was frontmost last, then hunt.

TabSwitcher shows a row of app tiles with live window previews. Rest on an app that has
several windows and a strip of those windows expands beneath it. `↓` steps into it,
arrows pick, release `⌥` switches. Type at any point to search every window by name.

## Build and run

```bash
bash Scripts/setup.sh          # once: creates a stable signing identity
open TabSwitcher.xcodeproj     # ⌘R to run
```

Command line:

```bash
bash Scripts/build.sh          # builds and signs into build/TabSwitcher.app
bash Scripts/build.sh --run
```

Headless check of what resolved and what discovery found — no GUI, no permissions
dialog:

```bash
build/TabSwitcher.app/Contents/MacOS/TabSwitcher --diagnose
```

## Keys

| Key | Action |
|---|---|
| `⌥Tab` | summon; again to move to the next app |
| `⌥⇧Tab` | previous app |
| rest on an app | reveals its windows after the dwell delay |
| `↓` | step into the window strip immediately |
| `↑` | back to the app row |
| `←` `→` | move within the strip |
| any letter | search every window by name |
| release `⌥`, or `↵` | switch |
| `esc` | cancel |

`Tab` always means "next app", in every state — it never changes meaning based on
something invisible.

## Layout

```
Packages/SwitcherCore/   pure decision logic. No AppKit, no accessibility, no capture.
                         The whole test suite runs in CI with no GUI session.
  Kernels/               one file per decision, each with a *Specs.md beside it
TabSwitcher/
  Platform/              the ONLY place private macOS APIs are touched
  Inventory/             window discovery and the store that keeps it warm
  Capture/               thumbnails: memory tier, disk tier, two capture backends
  Input/                 the event tap and its dedicated thread
  Overlay/               NSPanel + SwiftUI, driven by the state machine
  Focus/                 raising a specific window of a specific app
```

Two rules the architecture exists to enforce:

**Never look anything up while the user is pressing the key.** Discovery runs at launch
and on system events; the hotkey only reads memory. This is why SwiftUI is fast enough
here — the framework was never the bottleneck, doing work at the wrong moment was.

**Every decision is a pure function.** The entire dwell interaction lives in
`OverlayStateMachine` and is verified by 28 tests that never open a window.

## Tests

```bash
cd Packages/SwitcherCore && swift test
```

## Docs

- [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) — what's needed, and why signing matters
- [`docs/PRIVATE_APIS.md`](docs/PRIVATE_APIS.md) — which private calls, why, and what happens without them
