# Release and maintenance plan

What DockDoor and AltTab do, what of it applies to us, and what does not.

## What they have in common

Both ship Sparkle with an EdDSA-signed `appcast.xml` in the repository, keep a website in
the same repo on GitHub Pages, and drive a changelog from commits. AltTab automates the
whole release from conventional commits via `semantic-release`; DockDoor keeps a
`.release.json` and hand-rolled workflows, plus Crowdin for translations.

Both are notarized with a paid Developer ID. That is the difference that matters.

## Decisions

| | Chosen | Why |
|---|---|---|
| Signing | Self-signed, for now | No $99. Pipeline built so a Developer ID is a config change later, not a rewrite. |
| Updates | Sparkle, stable channel only | One channel is one less thing to operate wrong while there are few users. |
| Website | GitHub Pages from `docs/`, no custom domain | Free, nothing to renew. Gives the install command a home that is not a raw GitHub URL. |
| Commits | Prose, manual releases | The commits explain *why*, at length, and that has been worth more than automation on a single-author repo. Changelog stays hand-written. |

## The constraint self-signing imposes

TCC keys its grants to the code signature. Every release must be built with the **same**
signing identity, forever. Lose it or regenerate it and every existing user's
Accessibility and Screen Recording grants stop working — and the app looks broken rather
than unpermitted, because a denied permission and a revoked one are indistinguishable from
inside the app.

Three consequences:

1. **Releases are built locally, not in CI.** Putting the identity in GitHub secrets would
   put the thing that protects every user's permissions on a server, to save a manual step
   on a repo that publishes rarely. Not worth it.
2. **The identity must be backed up**, and `Scripts/setup.sh` must never silently create a
   second one over the top of the first.
3. **The app should check its own signature on launch.** Sparkle has a known failure mode
   where an in-place update leaves the outer bundle's sealed-resource manifest stale
   (sparkle-project, and imputnet/helium-macos#339), and the symptom is exactly the one
   above. Better to say so than to let the user conclude the app stopped working.

## What Sparkle cost, that was not visible when it was chosen

Self-signing and Sparkle together **force
`com.apple.security.cs.disable-library-validation`**. Library validation restricts a
process to loading code signed by the same Team ID; a self-signed certificate has no Team
ID, so the check rejects the app's own embedded Sparkle framework, signed by the app's own
identity. The app does not launch at all without the entitlement — `dyld` refuses with
"different Team IDs".

There is no third option. Disabling the hardened runtime instead is strictly worse, and
Sparkle's own documentation says the same thing: without an Apple Developer ID, library
validation and Sparkle cannot both be on.

What it costs: a library signed by anyone, or by nobody, can be loaded into a process that
holds Screen Recording and Accessibility. The rest of the hardened runtime stays on.

This is the clearest single thing the $99 buys, and the entitlement should be deleted the
day there is a Developer ID.

## Not doing

**Homebrew.** Casks have required notarization since September 2026. Closed until there is
a Developer ID.

**Automated releases in CI.** See above.

**Crowdin.** There is one locale and no translators. Extracting strings to a catalogue
comes first, and that is deferred.

**Delta updates.** Sparkle supports them; the app is 5MB. Nothing to save.

**swiftformat.** Both projects use it, and it was tried here: 44 of 49 files fail the lint
with any reasonable configuration. That leaves three options — a permanently red CI, a
mass-reformat commit that rewraps the explanatory comments this codebase leans on, or
tuning the rules until the existing code passes, which makes the tool decorative. A
formatter earns its keep when several people are writing the code; there is one. Revisit
when that changes, and take the reformat commit then, on its own, touching nothing else.

**A beta channel.** Add one when there is someone to beta test.

## Order

1. Repo hygiene — issue and PR templates, changelog, dependabot, swiftformat
2. Sparkle — keypair, Info.plist, updater, menu item, settings toggle, appcast
3. `release.sh` extended to sign and emit an appcast entry
4. The signature self-check
5. The landing page
