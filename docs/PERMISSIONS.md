# Permissions

| Permission | Needed for | Without it |
|---|---|---|
| **Screen Recording** | window thumbnails, and window *titles* from the Window Server | tiles fall back to app icons |
| **Accessibility** | minimized/main state, native tab detection, and the element used to raise a window reliably | switching still works through the private front-process call; titles still come from the Window Server |

Neither is fatal on its own, which is deliberate: a switcher that stops working because
a monthly consent dialog was dismissed is worse than one that loses its previews. The
two also cover for each other — titles come from whichever is available.

| Screen Recording | Accessibility | Result |
|---|---|---|
| yes | yes | everything |
| yes | no | previews and titles; no minimized or native-tab detection |
| no | yes | titles from accessibility, app icons instead of previews — fully usable |
| no | no | unusable |

## Why Screen Recording is unavoidable for previews

Going through private APIs does not avoid this permission, and it is worth being clear
why. The gate is not in the function you call — it is in WindowServer, which owns the
pixels. `CGSHWCaptureWindowList` is a WindowServer call, so it sits behind exactly the
same TCC check as ScreenCaptureKit. Using the private path buys access to *minimized
windows*, not freedom from the grant. Every comparable app is in the same position:
DockDoor gates its capture on `CGPreflightScreenCaptureAccess()` and tells the user
outright that "Screen Recording permission is required to show window thumbnails".

Both are granted to the **`.app` bundle**, never to a bare binary.

## Why signing matters more than it looks

macOS keys a TCC grant to the app's code signature — specifically its *designated
requirement*. For an ad-hoc signature that requirement is the cdhash, which changes on
every single build. The symptom is nasty because it is silent: the Accessibility toggle
stays visibly ON while every call returns `kAXErrorAPIDisabled`.

`Scripts/setup.sh` creates a stable self-signed identity so grants survive rebuilds.
Run it once.

The identity reports `CSSMERR_TP_NOT_TRUSTED` and is hidden by `security find-identity -v`.
That is expected: trust is a Gatekeeper concern, i.e. a *distribution* concern. TCC only
requires that the signature be stable.

### Verifying it took effect

Do not trust "signed with" — check the requirement TCC actually keys on:

```bash
codesign -d -r- build/TabSwitcher.app 2>&1 | grep designated
```

Good — identity-based, identical across rebuilds:

```
designated => identifier "dev.sagar.tabswitcher" and certificate leaf = H"62abfda3..."
```

Bad — ad-hoc, changes every build, grants keep evaporating:

```
designated => identifier "dev.sagar.tabswitcher" and cdhash H"a9295b18..."
```

Build twice and compare. If the lines differ, grants will not survive.

## Resetting during development

```bash
tccutil reset Accessibility dev.sagar.tabswitcher
tccutil reset ScreenCapture dev.sagar.tabswitcher
```

## Ongoing friction

macOS re-prompts for Screen Recording roughly **monthly**. Notarization does not exempt
an app; `com.apple.developer.persistent-content-capture` is the only exemption and is
not realistically obtainable for a utility. The app degrades to icons each time and
keeps working.

## Secure input

While any process holds secure input — a password field, 1Password, sometimes a
terminal that leaked it — macOS filters key events out of every event tap system-wide.
Typing to search stops working. Modifier tracking does not, so `⌥Tab` cycling still
works. The overlay says so explicitly rather than appearing broken.
