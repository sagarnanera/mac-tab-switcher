# AppGrouping — behavior spec

Flat window list → `[AppGroup]`, the structure the app row renders.

## Rules

1. **A window whose pid is not in `apps` is dropped.** We will not render a row we
   cannot label.
2. **Empty groups never appear.**
3. **App order** is `appMRU` position; apps absent from it sort after all present ones,
   in their relative order within `apps`.
4. **Window order within an app**: `windowMRU` → `.main` first → title → id. The last
   two make the order *total*, so repeated passes are identical. A list that reshuffles
   between summons destroys muscle memory.
5. **`breakOutNativeTabs: false`** keeps only the `.main` window of a tab set.
6. **`includeMinimized: false`** drops minimized windows before grouping, so they
   cannot resurrect an otherwise-empty group.

## Non-goals

Does not choose the selection (that starts at MRU[1], in `OverlayStateMachine`), does
not filter by query, does not size tiles.
