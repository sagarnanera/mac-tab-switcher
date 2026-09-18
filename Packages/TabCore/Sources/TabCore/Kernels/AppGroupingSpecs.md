# AppGrouping — behavior spec

Turns a flat window list into `[AppGroup]`: the app-grouped, MRU-ordered
structure the switcher's app row renders.

## Inputs

| Input | Meaning |
|---|---|
| `windows` | every window seen this enumeration pass, any order |
| `apps` | known running apps; also defines the tie-break order for apps absent from the MRU |
| `appMRU` | pids, most recently used first |
| `windowMRU` | window ids, most recently used first |
| `options` | `groupNativeTabs`, `includeMinimized` |

## Rules

1. **A window whose pid is not in `apps` is dropped.** We will not render a row we
   cannot label. This happens legitimately: ScreenCaptureKit reports windows owned
   by processes that are not user-facing applications.
2. **Empty groups never appear.** An app with no surviving windows contributes
   nothing, so the app row only ever shows apps you can actually switch to.
3. **App order** is `appMRU` position; apps absent from the MRU sort after all
   present ones, in their relative order within `apps`.
4. **Window order within an app** is, in precedence order:
   `windowMRU` position → `.main` first → title ascending → `windowID` ascending.
   The last two exist purely to make the order *total*, and therefore stable across
   passes. A list that reshuffles between summons destroys muscle memory, which is
   the only thing that makes a switcher fast to use.
5. **`groupNativeTabs: false`** keeps only the `.main` window of a native-tab set,
   so Finder with 6 tabs contributes 1 row rather than 6. When true (the default)
   every tab is its own row, because AX already hands them to us that way and they
   are genuinely separate destinations.
6. **`includeMinimized: false`** drops minimized windows before grouping, so they
   cannot resurrect an otherwise-empty group.

## Non-goals

- Does not decide which group is *selected* — that is `OverlayStateMachine`, which
  starts on MRU[1] so a quick tap toggles back to where you just were.
- Does not decide tile sizes or wrapping — that is `TileSizing`.
- Does not filter by search text — that is `FuzzyRank`.
