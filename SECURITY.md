# Security

## Reporting a vulnerability

Open a [private security advisory](https://github.com/sagarnanera/mac-tab-switcher/security/advisories/new).
Please do not open a public issue for anything exploitable.

Expect an acknowledgement within a week. This is a spare-time project, not a funded one —
that is the honest expectation to set rather than a service level nobody is on call for.

## What this app can do

Worth stating plainly, because the permissions it asks for are broad:

- **Screen Recording** lets it read the pixels of any window on the system. It uses this
  to make thumbnails. macOS draws no distinction between a thumbnail and a recording, so
  the permission granted is the broad one either way.
- **Accessibility** lets it read window titles and raise windows. The same permission
  would allow reading the contents of other apps' UI.
- It installs a **`CGEvent` tap** to see the ⌥ key. The tap is listen-only and filters to
  the modifier and the keys pressed while it is held.

## What it does not do

- **No network code at all.** The app makes no outbound connections of any kind. No
  telemetry, no crash reporting, no update check. There is no auto-updater; you update by
  re-running the install command. `nm -u` on the binary lists no networking symbols.
- **Thumbnails are cached to disk** under `~/Library/Caches/dev.sagar.tabswitcher`, so
  they survive a restart. They are pictures of your windows. Delete that directory to
  clear them.
- **Nothing is logged** beyond `/tmp/tabswitcher-status.txt`, which is written on launch
  for debugging and contains window titles. Delete it if that matters to you; it is
  rewritten on the next launch.
- **Secure Input is honoured.** When another app has Secure Input active — a password
  field — keystroke filtering stops and the overlay says so rather than silently
  continuing.

## Private APIs

The app calls seven undocumented SkyLight symbols, each resolved at runtime and each with
a public fallback. They are listed in `docs/PRIVATE_APIS.md`. They are used to raise a
specific window, capture minimized windows and determine Space membership — things macOS
provides no public API for. None of them exfiltrate anything; they are all local window
management.

## Unsigned builds

TabSwitcher is not currently notarized. Anything you install from a source other than this
repository's releases has not been verified by anyone. The install script prints the
checksum of what it downloads; compare it against the release page if you care to.

The app checks its own code signature on launch and says so if it has broken. That matters
more here than it would elsewhere: macOS ties permission grants to the signature, so a
damaged bundle keeps its Accessibility and Screen Recording grants on paper while being
refused them in practice, and the app simply appears to stop working.
