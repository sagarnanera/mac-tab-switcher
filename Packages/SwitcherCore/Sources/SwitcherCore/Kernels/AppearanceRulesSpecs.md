# AppearanceRules — behavior spec

How the overlay answers the three Accessibility display settings. One table, because
the whole point is that the rules are readable side by side rather than scattered
through view code.

| | default | reduce transparency | increase contrast |
|---|---|---|---|
| panel border opacity | 0.10 | 0.35 | 0.90 |
| panel border width | 1 | 1 | 1.5 |
| selection halo opacity | 0.55 | 0.55 | 1.0 |
| selection ring widths | 5 / 3 | 5 / 3 | 6 / 3.5 |
| unselected tile border | none | none | 0.45 |

Increase contrast wins wherever the two overlap: it is the stronger request.

## What is deliberately *not* here

**The panel fill.** `.regularMaterial` already goes opaque under Reduce Transparency —
AppKit does that for every material. Overriding it would mean reimplementing a system
behaviour that also tracks appearance and wallpaper tint, to arrive back where we
started. What the system does not supply is an edge, and an opaque HUD has lost the
depth cue that separated it from the window behind it. So the border varies, the fill
does not.

**The two-tone selection ring at default settings.** The halo is not an accessibility
concession; it is there always. A single accent-coloured ring is drawn straight onto a
window screenshot, and a blue ring on a blue screenshot is invisible to everyone. The
halo is the window background colour, so it is near-black in dark appearance and
near-white in light — whichever ring the thumbnail swallows, the other one holds.

## Motion

`stripRevealDuration` is 120ms, or nil under Reduce Motion. Nil means an instant swap,
not a slower fade: a longer animation is more motion, not less.

Measured on macOS 27 with Reduce Transparency on, in a real `.nonactivatingPanel`:
`.glassEffect` does **not** go opaque — it keeps tinting from the backdrop, lands at
`#2C1E21` against `#393939` for `.regularMaterial`, and drops secondary caption text to
3.69:1 where the material holds 5.65:1. That is below the 4.5:1 floor, and it varies
with whatever window happens to be behind the overlay. Hence material, not glass.

## Why a kernel and not view code

Every branch here is unreachable on a machine at default settings. Without a test, the
only way to check a change is to alter your own system preferences and look — which
nobody does, and CI cannot. `--demo-a11y=contrast,transparency,motion` covers the
looking; the tests cover the rest.
