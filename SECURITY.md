# Security

## Reporting a vulnerability

Open a [private security advisory](https://github.com/sagarnanera/tab-switcher/security/advisories/new).
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
- **Library validation is disabled** (`com.apple.security.cs.disable-library-validation`).
  This is a real weakening and worth understanding. Library validation restricts a process
  to loading code signed by the same Team ID; a self-signed certificate has no Team ID, so
  the check rejects even the app's own embedded Sparkle framework. Without an Apple
  Developer ID there is no configuration in which both auto-updates and library validation
  work. With the entitlement on, a library signed by anyone — or by nobody — could be
  loaded into a process that holds Screen Recording and Accessibility. It will be removed
  the day this app has a Developer ID.

## What it does not do

- **No telemetry and no crash reporting.** The only outbound connection the app ever makes
  is Sparkle's update check, and automatic checking is **off** until you turn it on —
  Sparkle asks on second launch rather than assuming. Nothing about you is sent with it.
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

## Updates

Updates are verified by an EdDSA signature against a public key compiled into the app.
Because this app is not notarized, Apple has vouched for nothing, and that signature is the
only thing standing between the update feed and arbitrary code running on every install.

The private half lives in the maintainer's login keychain and is not in this repository.
It is a **second trust root**, independent of the code signing certificate: whoever holds
it can ship code to every installation.

## Unsigned builds

TabSwitcher is not currently notarized. Anything you install from a source other than this
repository's releases has not been verified by anyone. The install script prints the
checksum of what it downloads; compare it against the release page if you care to.

The app checks its own code signature on launch and says so if it has broken. That matters
more here than it would elsewhere: macOS ties permission grants to the signature, so a
damaged bundle keeps its Accessibility and Screen Recording grants on paper while being
refused them in practice, and the app simply appears to stop working.
