# DwellPolicy — behavior spec

When resting on an app reveals its windows.

| Mode | Behavior |
|---|---|
| `.delayed(d)` | arm a timer for `d`; reveal on expiry. Default 500ms. |
| `.instant` | reveal as soon as an expandable app is selected |
| `.manual` | never reveal on its own; `↓` and hover are the only ways in |

`delay` returns nil for `.instant` and `.manual` — "do not arm a timer". The caller
feeds `dwellElapsed` straight back for `.instant`, and not at all for `.manual`.

## Clamping

User input is clamped to 150–2000ms. Below ~150ms the strip flickers open while
merely passing through an app on the way somewhere else. Above ~2s nobody discovers
the feature exists.

## Why this is its own type

Dwell timing is the single most likely thing to be wrong, and it should be tuned from
measurements — how often a reveal is followed by an actual selection from the strip —
rather than from scattered `asyncAfter` calls that are hard to find and harder to
change.
