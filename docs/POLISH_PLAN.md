# Polish plan — modern macOS standards

The app works. It looks like a developer build. This is the gap, in the order worth
closing it.

Verified on this machine: macOS 27.0, Xcode 26.5 (macOS 26.5 SDK), Icon Composer and
`ictool` present, `notarytool` 1.1.2.

**Xcode 27 is not a prerequisite.** Building against the 26.5 SDK on macOS 27 is fine —
apps are forward-compatible. Upgrading buys newer APIs, not correctness.

---

## A. Identity — icon and menu bar

macOS 26 replaced flat `.icns` with a **layered bundle the system composites**: you
supply flat artwork, macOS applies the squircle mask, glass material, shadow and
specular highlight per appearance. Never pre-round corners or bake a shadow.

`AppIcon.icon` is a *folder* containing `Assets/` plus `icon.json` — plain JSON
referencing SVG layers. That matters: it can be written directly, without the Icon
Composer GUI.

- [ ] Generate layered SVG artwork (stacked-windows mark, background gradient +
      foreground glyph)
- [ ] Hand-write `AppIcon.icon/icon.json`, using Maccy's shipping file as the template
- [ ] **Also** generate `Assets.xcassets/AppIcon.appiconset` — our deployment target is
      macOS 14, and `.icon` only applies on 26+
- [ ] Wire into the project: add `.icon` to Resources, set
      `EXCLUDED_SOURCE_FILE_NAMES = AppIcon.icon` so its SVGs aren't compiled as
      sources, keep `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
- [ ] Separate **menu bar glyph**, monochrome, `isTemplate = true`, ~16–18pt. Never the
      app icon shrunk down.

Two traps: `ictool` export omits the transparent margin Xcode adds at build time, so
exported PNGs come out oversized — export via a real build instead. And reports
conflict on whether SVG layers pick up glass correctly; test PNG layers if they don't.

## B. Look — Liquid Glass, carefully

- [ ] **Test `.glassEffect` in our non-activating panel before adopting it.** There is a
      known bug where it degrades to a plain blur while the app is not frontmost — and
      our panel is *never* frontmost by design. If it bites, `NSVisualEffectView` with
      the `.hudWindow` material stays correct and idiomatic for a transient HUD.
- [ ] Honour `accessibilityReduceTransparency` → opaque background
- [ ] Honour `colorSchemeContrast == .increased` → opaque plus stronger borders
- [ ] Honour `accessibilityReduceMotion` → no fade or scale, snap instead

Note for later: `UIDesignRequiresCompatibility` (the Liquid Glass opt-out) is **ignored**
when building against the macOS 27 SDK, so an upgrade is one-way on appearance. macOS 27
also gives users an opacity slider — translucency cannot be assumed fixed.

## C. First run

The single worst moment in the app today, and the one that cost real time during
development: Accessibility prompts silently, Screen Recording never prompts at all, and
nothing explains what either is for.

- [ ] Welcome window on first launch: what the app does, then both permissions with live
      status and a one-click grant each
- [ ] A "press your shortcut" step that confirms the overlay actually appeared — proof it
      works, not just a claim
- [ ] Re-openable from the menu bar, since permissions can lapse

## D. Text and accessibility

- [ ] Extract all UI strings to `Localizable.xcstrings`; ship English only. Translation
      then becomes a data change rather than touching every view.
- [ ] `InfoPlist.xcstrings` for the permission usage strings
- [ ] VoiceOver on the overlay: `accessibilityRole = .list`, each tile a `.button` with
      window title plus app name as its label, and post `.layoutChanged` when the panel
      appears — an overlay that announces nothing is invisible to a screen reader

## E. Repository and distribution

- [ ] README with an animated demo above the fold, install instructions, a plain
      explanation of why each permission is needed, and a FAQ
- [ ] `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`
- [ ] CI: build, test, lint, dead-code check

Distribution is gated on one decision — see below.

## F. Later

- [ ] Sparkle auto-updates. Note the EdDSA key is a **second trust root** independent of
      the signing certificate: whoever holds it can push code to every install.
- [ ] App Intents — a `SwitchToWindowIntent` would appear in Spotlight and Shortcuts for
      roughly 200 lines, and macOS 27 extends the same definitions to Siri.

---

## The distribution decision

Everything here is downstream of whether the app is notarized, which needs a $99/year
Apple Developer ID.

**Without it:**
- A browser download is **blocked**. macOS removed the Control-click bypass; the user
  must visit System Settings → Privacy & Security → Open Anyway and authenticate. For an
  app that then asks for Accessibility *and* Screen Recording, that is three alarming
  dialogs before first use.
- **Homebrew is closed.** Casks have required notarization since 1 September 2026.
- A `curl | bash` installer **does work**, and not by a trick: the quarantine flag is set
  by the downloading application, and `curl` does not set it. An app fetched by a script
  and moved to `/Applications` is never quarantined, so Gatekeeper never challenges it.

So without the $99, a shell installer is not merely a convenience — it is the only
install path that works at all. That is worth knowing before choosing.

**The honest caveat:** piping a remote script into a shell runs whatever that URL serves,
unreviewed, and this app asks for permissions that can watch the screen and read window
contents. The precedent (Homebrew, rustup) makes it normal, not safe. If we ship one:
keep the script in the repo, show its full source on the site, publish a checksum, and
document the inspect-then-run form as the default with the one-liner as the shortcut.
