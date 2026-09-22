# TabSwitcher

A window switcher for macOS with previews. ⌥Tab cycles apps; rest on one with several
windows and its windows appear beneath, still under the same key.

<!-- TODO: demo.gif — ⌥Tab through the app row, pause on a multi-window app, step into the
     strip, release. Recorded at 1400px wide, under 5MB, no cursor. -->

![Demo](docs/demo.gif)

## Why

⌘Tab shows icons, not windows. If you have five VS Code windows open it offers you one
entry and no way to say which. TabSwitcher shows what each window actually contains, and
reaches individual windows of the same app without leaving the keyboard.

## How it works

Two levels, one key.

| | |
|---|---|
| `⌥Tab` | next app |
| `⌥⇧Tab` | previous app |
| hold on an app with several windows | after a moment its windows appear below |
| `⌥Tab` again, once they have appeared | steps through *those* windows |
| `⌥1`–`⌥9` | jump straight to a window in the strip |
| type anything | filter every window by name |
| `↑` | back up to the app row |
| release `⌥` | switch |
| `esc` | cancel |

The dwell before windows appear is configurable, including "never" (use `↓` or the mouse)
and "immediately". Settings → Behavior.

## Install

**No notarized build yet.** TabSwitcher is not signed with an Apple Developer ID, which
has consequences worth knowing before you install:

- A build downloaded through a browser is **blocked** by Gatekeeper, and recent macOS
  removed the Control-click bypass. You would have to go to System Settings → Privacy &
  Security → Open Anyway and authenticate.
- Homebrew is not an option; casks have required notarization since September 2026.

The install script avoids this legitimately rather than by a trick: quarantine is applied
by the *downloading application*, and `curl` does not apply it. Nothing is bypassed.

**Read it first, then run it.** This is the honest form, and the one to prefer:

```bash
curl -fsSL https://raw.githubusercontent.com/sagarnanera/tab-switcher/main/Scripts/install.sh -o install.sh
less install.sh
bash install.sh
```

The one-liner, if you have already read the script:

```bash
curl -fsSL https://raw.githubusercontent.com/sagarnanera/tab-switcher/main/Scripts/install.sh | bash
```

Piping a remote script into a shell runs whatever that URL serves at that moment. The
precedent — Homebrew, rustup — makes it normal, not safe. It is worth being deliberate
about here in particular, because this app asks for permissions that can read your screen.

### Or build it yourself

Requires Xcode 16 or newer. macOS 14+.

```bash
git clone https://github.com/sagarnanera/tab-switcher
cd tab-switcher
bash Scripts/setup.sh          # once: creates a stable signing identity
bash Scripts/build.sh          # builds, signs, installs to ~/Applications
bash Scripts/build.sh --run
```

Or `open TabSwitcher.xcodeproj` and ⌘R.

Headless check of what resolved and what discovery found — no GUI, no permission dialog:

```bash
~/Applications/TabSwitcher.app/Contents/MacOS/TabSwitcher --diagnose
```

## Quitting it

TabSwitcher is a menu bar agent with no Dock icon, so there are three ways out:

- the **stacked-squares icon** in the menu bar → Quit TabSwitcher
- Settings → Quit TabSwitcher
- `bash Scripts/quit.sh`

The last one exists on purpose. A menu bar item can end up unreachable — pushed under the
notch on a crowded menu bar — and an app you cannot quit is worse than one that does not
run.

## Permissions

Two, and the app tells you what each is for on first run rather than prompting cold.

**Accessibility** — required to *raise* a window. macOS has no public way to bring one
specific window of an app forward; it goes through the accessibility API. Without it the
app still runs, using a fallback that is less reliable across Spaces.

**Screen Recording** — required for the previews. macOS treats reading the pixels of
another app's window as screen recording, whatever the purpose. Without it you get app
icons instead of thumbnails, and on some systems window titles disappear too.

Neither permission sends anything anywhere. There is no network code in this app.

`docs/PERMISSIONS.md` has the detail, including what degrades and how.

## FAQ

**Does it switch browser tabs?**
No. A background tab has no capturable pixels by any mechanism — not ScreenCaptureKit, not
accessibility, not even a browser extension. See `ARCHITECTURE.md` §8.

**Why does it want Screen Recording just to show small pictures?**
Because macOS makes no distinction between a thumbnail and a recording. The same
permission covers both.

**Does it use private APIs?**
Yes, seven of them, each behind a runtime check with a public fallback. `docs/PRIVATE_APIS.md`
lists every one, what it does, and what happens when it disappears. The same symbols have
shipped in AltTab and DockDoor for years.

**Will it survive a macOS update?**
The private calls are resolved with `dlsym` at runtime, never linked. If one vanishes the
app loses that capability and keeps running; it does not fail to launch. Run
`TabSwitcher --diagnose` to see which paths are live.

**How do I quit it?**
Menu bar icon → Quit, or `bash Scripts/quit.sh`. It has no Dock icon by design.

**Where are the settings?**
Menu bar icon → Settings. Shortcut, dwell timing, preview size, launch at login.

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
  Welcome/               the guided first run
```

Two rules the architecture exists to enforce:

**Never look anything up while the user is pressing the key.** Discovery runs at launch
and on system events; the hotkey only reads memory. This is why SwiftUI is fast enough
here — the framework was never the bottleneck, doing work at the wrong moment was.

**Every decision is a pure function.** The whole interaction model lives in
`OverlayStateMachine` and is verified by tests that never open a window.

```bash
cd Packages/SwitcherCore && swift test
```

## Docs

| | |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | the shape of the app, and the decisions that look arbitrary but are not |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | how to work on it, and the four rules CI enforces |
| [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) | what is needed, what degrades without it, and why signing matters |
| [`docs/PRIVATE_APIS.md`](docs/PRIVATE_APIS.md) | which private calls, why, and what happens when one disappears |
| [`SECURITY.md`](SECURITY.md) | what this app can see, and what it does not do |

## License

MIT. See `LICENSE`.
