# Contributing

## Start here

`ARCHITECTURE.md` explains the shape of the app in one read. It is written so you do not
have to go through the code to find out why something is the way it is — in particular
§6, which lists decisions that look arbitrary and are not, and §7, the macOS behaviours
that each cost a debugging session to discover.

## Build and test

```bash
cd Packages/SwitcherCore && swift test     # 73 tests, no GUI, no permissions
bash Scripts/setup.sh                      # self-signed identity, once
bash Scripts/build.sh                      # build, sign, install to ~/Applications
bash Scripts/quit.sh
```

## The rules CI enforces

Four, and they are checked mechanically rather than in review:

1. **`SwitcherCore` imports no OS frameworks.** No AppKit, SwiftUI, ApplicationServices,
   ScreenCaptureKit or Carbon. This is what lets the logic be tested with no GUI session,
   no permissions and no Xcode project.
2. **Private symbols live in `Platform/PrivateAPI.swift` and nowhere else.** Every one is
   resolved with `dlsym` and guarded by a capability check. Never `@_silgen_name`: a
   missing symbol then fails at *launch* rather than at the call site.
3. **Strict concurrency stays on.**
4. The app target builds.

## What belongs where

| | |
|---|---|
| A decision with rules | `Packages/SwitcherCore/Kernels/`, with a `*Specs.md` beside it and tests |
| Anything touching an OS framework | `TabSwitcher/` |
| Anything touching a private symbol | `Platform/PrivateAPI.swift`, only |

The kernels exist because most of this app's behaviour is impossible to test through the
UI — it needs a logged-in GUI session, granted permissions, and windows in known states.
Anything that can be a pure function should be one.

## Things worth knowing before you change something

- **`--diagnose` reports the permissions of the terminal that launched it**, not the
  app's. TCC attributes to the responsible process. For the app's own view, read
  `/tmp/tabswitcher-status.txt`, which it writes on every launch. This has misled people
  more than once, including while the app was being written.
- **`@Observable` does not instrument `_modify`.** Mutating nested state in place emits no
  change notification and the overlay silently stops re-rendering. Read, modify, write
  back. `OverlayController.dispatch` shows the pattern.
- **Accessibility settings are unreachable on a default Mac.** Use
  `--demo-a11y=contrast,transparency,motion` rather than changing your own system
  preferences, and add the rule to `Kernels/AppearanceRules.swift` rather than to a view.
- **`--dump-a11y` writes what a screen reader would find** to
  `/tmp/tabswitcher-a11y.txt`, so you do not have to switch VoiceOver on to check a label.

`ARCHITECTURE.md` §9 lists every debug flag.

## Commits

Explain *why*, not what — the diff already says what. If a change reverses an earlier
decision, say which and why, so the next person does not reverse it back. If it changes
something `ARCHITECTURE.md` describes, update that document in the same commit; a doc that
is updated separately is a doc that stops being true.

## Reporting a bug

Include the output of:

```bash
/Applications/TabSwitcher.app/Contents/MacOS/TabSwitcher --diagnose
cat /tmp/tabswitcher-status.txt
```

and your macOS version. Window enumeration differs by OS version, by permission state and
by which apps are running, so a description without this is usually not reproducible.
