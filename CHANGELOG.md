# Changelog

Hand-written, and kept to what a user would notice. Internal refactors are in the git
history where they belong.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [semantic versioning](https://semver.org/).

## [Unreleased]

### Fixed

- The window strip sometimes opened and closed too fast to see, or stepped in at the
  second or third tile. A stationary mouse pointer was enough to cause both.
- Preview sizes above about 300pt overflowed the settings pane and distorted the sample.
- The settings sidebar jerked when collapsed or reopened. It no longer collapses, which
  is also how System Settings behaves.

## [0.1.0] — unreleased

First release.

### Added

- Two-level window switching on one key. `⌥Tab` cycles apps; rest on an app with several
  windows and its windows appear beneath, then `⌥Tab` steps through those.
- Live previews of every window, including minimized ones and windows on other Spaces.
- `⌥1`–`⌥9` to jump straight to a window in the strip.
- Type anything to filter every window by name.
- A guided first run that explains each permission before asking for it, and confirms the
  shortcut actually works rather than claiming it does.
- Settings: shortcut, dwell timing (including "never" and "immediately"), preview size,
  key hints, launch at login.
- Works with degraded permissions rather than refusing to start. Without Screen Recording
  you get app icons instead of thumbnails; without Accessibility, raising falls back to a
  less reliable path.
- Honours Reduce Transparency, Increase Contrast and Reduce Motion.
- Screen reader labels on every tile.
- A check of the app's own code signature on launch, because a damaged bundle loses its
  permissions silently and otherwise just looks broken.
- No network code of any kind. No telemetry, no update check.

### Known limitations

- **Not notarized.** A browser download is blocked by Gatekeeper and Homebrew is not
  available. The install script is the path that works.
- **No browser tab switching.** A background tab has no capturable pixels by any
  mechanism. See `ARCHITECTURE.md` §8.
- **No auto-update.** Re-run the install command to update; it replaces the app in place
  and keeps your permissions. There is no notification when a new version exists.
- **VoiceOver does not follow the selection.** Tiles are labelled, but `Tab` moves the
  app's own selection without moving system focus, so a screen reader will not announce
  each step.

[Unreleased]: https://github.com/sagarnanera/mac-tab-switcher/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sagarnanera/mac-tab-switcher/releases/tag/v0.1.0
