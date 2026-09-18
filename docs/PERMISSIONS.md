# Permissions

TabSwitcher needs two, and neither can be worked around.

| Permission | Needed for | Without it |
|---|---|---|
| **Accessibility** | window titles, minimized/main state, native tabs, and raising a window | the switcher can see that windows exist but cannot label or switch to them |
| **Screen Recording** | window thumbnails | falls back to app icons; everything else keeps working |

Both are granted to the **.app bundle**, not to the `swift build` binary. Always
launch `build/TabSwitcher.app`.

## Why signing matters more than it looks

macOS keys a TCC grant to the app's code signature — specifically its designated
requirement. For an **ad-hoc** signature that requirement is the cdhash, which changes
on every single build. The symptom is nasty because it is silent: the Accessibility
toggle stays visibly ON while every AX call returns `kAXErrorAPIDisabled`.

`Scripts/make-signing-identity.sh` creates a stable self-signed identity so grants
survive rebuilds. Run it once.

The identity reports `CSSMERR_TP_NOT_TRUSTED` and is hidden by
`security find-identity -v`. That is expected and harmless: trust is a Gatekeeper
concern, i.e. a distribution concern. TCC only cares that the signature is stable.

### One-time keychain authorization

The first `codesign` against a freshly imported identity needs permission to use its
private key. Run the bundler **from your own Terminal** (not from an automated
session) so the keychain dialog can appear, and click **Always Allow**:

```bash
bash Scripts/bundle.sh
```

If it fails with `errSecInternalComponent`, the dialog never appeared. Authorize
non-interactively instead — this takes your login password:

```bash
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(security find-generic-password -w 2>/dev/null || true)" ~/Library/Keychains/login.keychain-db
```

## Granting

1. `bash Scripts/bundle.sh && open build/TabSwitcher.app`
2. Accept the Accessibility prompt, or add the app manually:
   System Settings → Privacy & Security → Accessibility
3. For thumbnails (Phase 3): System Settings → Privacy & Security → Screen Recording

## Resetting during development

```bash
tccutil reset Accessibility dev.nanera.tabswitcher
tccutil reset ScreenCapture dev.nanera.tabswitcher
```

## Known ongoing friction

macOS re-prompts for Screen Recording roughly **monthly**. Notarization does not
exempt an app; the `com.apple.developer.persistent-content-capture` entitlement is
the only exemption and is not realistically obtainable for a utility. The app is built
to degrade to icons whenever the grant lapses, rather than to break.
