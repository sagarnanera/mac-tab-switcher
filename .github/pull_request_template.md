## What and why

<!-- The diff says what changed. Say why it needed to. If this reverses an earlier
     decision, name it and say why — ARCHITECTURE.md §6 lists the ones already reversed
     once, and the reasoning that was overturned is still persuasive. -->

## Checks

- [ ] `cd Packages/SwitcherCore && swift test` passes
- [ ] New decision logic went into a kernel with tests, not into a view
- [ ] No private symbol is called outside `Platform/PrivateAPI.swift`
- [ ] `ARCHITECTURE.md` updated in this PR, if this changes something it describes

## How you tested it

<!-- Most of this app cannot be tested through the UI without a logged-in session,
     granted permissions and windows in known states. Say what you actually ran:
     a debug flag, a real switch across Spaces, a specific app with several windows. -->
