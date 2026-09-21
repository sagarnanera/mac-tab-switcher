# Welcome window — plan

## Why

Today the first launch prompts for Accessibility with no explanation and never mentions
Screen Recording at all. That combination cost real time during development, by someone
who wrote the app. For anyone else it means previews silently never appear, with nothing
saying why.

The second problem is subtler and probably costs more users: **the interaction is novel**.
Nobody expects "pause on an app and its windows appear". Someone who grants both
permissions and never discovers that has an app no better than Cmd+Tab.

## Structure — four paged steps

Multi-step flows want a step indicator and back navigation, and complex setup should
disclose progressively rather than arriving all at once. Five screens is too much
clicking for a utility, so the two permissions share a step: they are the same kind of
decision, and seeing both at once is less daunting than discovering a second after
granting the first.

1. **Welcome** — one sentence on what the app does, so the permission requests have
   context instead of arriving cold.
2. **Permissions** — both, with live status, a grant button each, and a line on what is
   lost by skipping. Continue is never blocked: the app works without either.
3. **The gesture** — a looping animation of tap-to-skim versus pause-to-expand. This is
   the differentiator and it is much easier to show than to describe.
4. **Try it** — "hold ⌥ and tap Tab", which detects that the overlay really appeared and
   confirms it. Turns "I think it's set up" into proof, and catches a dead shortcut
   immediately rather than leaving it to look like the whole app is broken.

Progress dots, Back, and Skip on every step. Nothing here is mandatory, so trapping
someone in it would be wrong.

## Behaviour

- Shown once, on first launch, gated by a preference.
- Re-openable from the menu bar, since permissions lapse and the gesture is worth
  revisiting.
- Non-blocking — the app runs normally while it is open.
- Becomes a regular app while open, as Settings does; an accessory app cannot bring a
  window to the front.

## When a permission lapses later

macOS re-prompts for Screen Recording roughly monthly and the grant can lapse. The
welcome window does **not** reappear — a window arriving unbidden a month later is worse
than the lapse. Instead the menu bar icon carries a badge and the menu names what is
missing, which is already half-built.

## Accessibility

- Respect Reduce Motion: the gesture animation becomes a static before/after.
- Every step reachable and readable by VoiceOver; the verification step announces
  success rather than only showing a tick.
- Status conveyed by icon and words, never colour alone.

## Files

| File | Purpose |
|---|---|
| `Welcome/WelcomeWindowController.swift` | Window lifecycle, activation policy, first-run gating |
| `Welcome/WelcomeView.swift` | The four steps and their navigation |
| `Welcome/GestureDemo.swift` | The looping animation, with a reduced-motion fallback |
| `Welcome/WelcomeModel.swift` | Step state, live permission status, verification signal |

`OverlayController` gains a callback fired when a session is summoned, so step 4 can
observe a real summon rather than guessing.

## Out of scope

Settings tour — a pass over dwell timing and tile size before the user has any feel for
the app would be ignored. The Settings window explains itself.
