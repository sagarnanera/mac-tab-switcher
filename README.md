# TabSwitcher

A macOS window switcher with previews and two-level drill-down.

`Cmd+Tab` switches between *apps*. With two VS Code windows open you can reach the
app but not a specific window. TabSwitcher shows a row of app tiles with live window
previews; rest on an app that has several windows and a strip of those windows expands
below it.

**Status: Phase 1** — window inventory and the raise path. No overlay, no hotkey, no
thumbnails yet. The demo is a diagnostic list window.

## Build and run

```bash
bash Scripts/make-signing-identity.sh   # once — see docs/PERMISSIONS.md
bash Scripts/bundle.sh
open build/TabSwitcher.app
```

Headless check, no GUI or permissions dialog required:

```bash
./build/TabSwitcher.app/Contents/MacOS/TabSwitcher --dump
```

## Tests

```bash
cd Packages/TabCore && swift test
```

## Layout

```
Packages/TabCore/     pure decision logic — no AppKit, no AX, no ScreenCaptureKit.
                      Runs in CI with no GUI session. This is where the tests live.
Sources/TabSwitcher/  everything that touches the OS.
  Inventory/          ScreenCaptureKit + Accessibility + NSWorkspace, merged
  Focus/              raising a specific window of a specific app
  UI/                 Phase 1 diagnostic window (thrown away in Phase 2)
```

The split is the point: every decision worth testing is a pure function over
primitives, and the OS-facing layer is deliberately untested (Humble Object). See
`Packages/TabCore/Sources/TabCore/Kernels/*Specs.md`.

## Docs

- [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) — what's needed and why signing matters
