# OverlayStateMachine — behavior spec

The whole interaction model, as a pure function of `(state, input)`. The dwell timer
is an *effect* the host arms, and its expiry comes back as an input — which is what
makes "does dwell fire when it should" a unit test instead of a stopwatch.

## The four rules that make dwell feel right

1. **Dwell reveals; it does not focus.** If dwell moved the selection into the strip,
   releasing the modifier would switch to a window the user never chose. Revealing is
   safe, focusing is a deliberate `↓`.
2. **Dwell only arms for apps with ≥2 windows.** Single-window apps never expand, so
   nothing ever moves under a user's aim for no reason.
3. **The cycle key progressively flattens.** Tap it quickly and it walks apps. Pause
   on an app with several windows, dwell reveals its strip, and the same key then
   walks *through those windows* before continuing to the next app.

   An earlier version forbade this, on the grounds that a key whose meaning depends on
   invisible state cannot be pressed quickly. The state is not invisible: the meaning
   changes exactly when the strip appears on screen. What the rule cost was that
   reaching a window required an arrow key — the other hand, away from the modifier —
   which defeats the point of a switcher.

   Walking off the end continues to the next app rather than wrapping, so the user is
   never trapped inside one app's windows.
4. **`↑` leaves the strip but does not hide it.** It is already on screen; removing it
   would make the row jump under someone who is still deciding.

## Selection

`.grouped(app:window:)` while browsing — `window == nil` means focus is on the app row
itself. `.flat(index)` while filtering, where the app/window distinction stops being
meaningful.

## Commit semantics

| Selection | Release modifier / Enter switches to |
|---|---|
| app row, no strip | that app's most recent window |
| app row, strip revealed but not entered | still that app's most recent window |
| inside the strip | that exact window |
| filtering | the highlighted result |

## Typing takes over the session

The first typed character sets `isSticky`, after which releasing the modifier no
longer commits. You cannot hold Option and type a query; without this a release
mid-query would fire a switch the user never asked for. Deleting back to an empty
query returns to the grouped view but *stays* sticky — re-arming modifier-release
once the user has shown they are typing would be a trap.

## Refresh during a session

`snapshotChanged` pins the selection to the same window id across the refresh. A list
that re-sorts under the user mid-switch is worse than a slightly stale one. If that
window is gone, the selection clamps to a valid neighbour. If every window is gone,
the overlay hides.

## Non-goals

- Does not own timing — `armDwell`/`cancelDwell` are effects; duration is `DwellPolicy`.
- Does not rank — that is `FuzzyRank`.
- Does not size tiles — that is `TileSizing`.
