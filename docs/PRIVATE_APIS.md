# Private APIs

TabSwitcher uses eight undocumented macOS symbols. This documents each one, why no
public API will do, and what the app does when it is missing.

## The firewall

Every private symbol is resolved in exactly one file, `TabSwitcher/Platform/PrivateAPI.swift`.

Resolution is by **`dlsym`, never `@_silgen_name`**. That choice is the whole safety
story: `@_silgen_name` links the symbol at build time, so a future macOS that removes
it makes the app fail to *launch* — dyld kills the process before `main` runs. `dlsym`
resolves at runtime and returns nil, so the call site falls back to a public API and
the app keeps working with one degraded feature instead of none.

Check what resolved on any machine:

```bash
build/TabSwitcher.app/Contents/MacOS/TabSwitcher --diagnose
```

## The symbols

| Symbol | Why | Without it |
|---|---|---|
| `CGSHWCaptureWindowList` | Reads the compositor's backing store — the only way to get pixels for a **minimized** window. ScreenCaptureKit's stream pauses while a window is minimized, so there is nothing for it to capture. | Falls back to ScreenCaptureKit. Thumbnails still work for visible and occluded windows; minimized windows show the app icon. |
| `CGSMainConnectionID` | Required argument for every other CGS call. | Disables the whole CGS group. |
| `_AXUIElementGetWindow` | Maps an accessibility element to the `CGWindowID` the Window Server knows it by. No public API exposes this. | Falls back to matching on title and geometry within the same process. Works, but ambiguous for identical untitled windows. |
| `CGSCopySpacesForWindows` | Which Spaces a window belongs to. | Windows on other Spaces lose their badge and, more importantly, the brute-force probe below is never triggered for them. |
| `CGSCopyManagedDisplaySpaces` | Which Spaces are currently visible. | Same. |
| `_AXUIElementCreateWithRemoteToken` | Fabricates an accessibility element for a window the normal window list will not return. The accessibility API only ever describes the **current Space**, so this is the only route to a window on another one. | Windows on other Spaces still appear (the Window Server sees them) but have no element, so they cannot be raised via accessibility — only via the front-process call below. |
| `_SLPSSetFrontProcessWithOptions` | Fronts a process *and* names a specific window, which is what makes macOS follow it to another Space. The public cooperative-activation APIs raise an app but never a chosen window. | Falls back to `NSRunningApplication.activate`, which raises the app and lands on whichever window it last had frontmost — i.e. the exact problem this app exists to solve, for cross-Space cases. |
| `SLPSPostEventRecordTo` | Makes a window *key* by posting a synthetic click. Fronting alone does not give a window keyboard focus. | The window comes forward but may not accept typing until clicked. |
| `GetProcessForPID` | Produces the `ProcessSerialNumber` the two `SLPS` calls require. Deprecated before macOS 10.9 and marked unavailable in Swift, but still exported. | Disables both `SLPS` calls. |

## Two details that look like magic numbers

**The Spaces mask is 7** (`current | others | user`) and must not be widened. Broader
masks silently return *nothing* for windows on other Spaces — the exact case the call
exists to answer.

**The synthetic click lands at (-1, -1)**, just outside the window frame. Clicking
inside hit-tests the window's content, and at the top-left corner that means pressing
the close button of Chrome PWA shims. The byte offsets in that event record are an
undocumented struct layout, originally worked out by Hammerspoon.

## Risk

These same symbols have shipped in AltTab (7.4M downloads) and DockDoor for years,
across macOS 12 through 27, without moving. That is the evidence base — not a
guarantee.

The deliberate cost of using them: the Mac App Store is permanently out, since private
API use is an automatic rejection. TabSwitcher could not be sandboxed anyway — the
sandbox blocks the accessibility and capture access the app is built on.
