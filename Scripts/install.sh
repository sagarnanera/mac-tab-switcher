#!/usr/bin/env bash
#
# TabSwitcher installer.
#
# Downloads the latest release, verifies its checksum and installs it. Nothing here
# needs sudo, nothing is written outside the install directory and the cache, and no
# Gatekeeper check is bypassed — quarantine is applied by the downloading application,
# and curl does not apply it.
#
# Read before running:
#   curl -fsSL https://raw.githubusercontent.com/sagarnanera/mac-tab-switcher/main/Scripts/install.sh -o install.sh
#   less install.sh
#   bash install.sh

set -euo pipefail

REPO="sagarnanera/mac-tab-switcher"
APP="TabSwitcher.app"
BUNDLE_ID="dev.sagar.tabswitcher"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preconditions -----------------------------------------------------------------

[ "$(uname -s)" = "Darwin" ] || die "TabSwitcher is macOS only."

major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || die "Requires macOS 14 or newer (found $(sw_vers -productVersion))."

case "$(uname -m)" in
  arm64|x86_64) ;;
  *) die "Unsupported architecture: $(uname -m)" ;;
esac

# Prefer /Applications, fall back to the user's own without asking for a password. The
# location makes no difference to permissions: TCC keys its grants to the bundle id and
# the code signature, not the path.
if [ -w /Applications ]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

# --- scratch space -----------------------------------------------------------------

tmp=$(mktemp -d)
TMPDIR_RELEASE="$tmp"
trap 'rm -rf "$tmp"' EXIT

# --- find the release --------------------------------------------------------------

say "Looking up the latest release of $REPO"
api="https://api.github.com/repos/$REPO/releases/latest"

# Status and body are captured separately so the failure message says which thing went
# wrong. "Are you online?" in response to a 404 sends people to debug the wrong problem.
http=$(curl -sSL --proto '=https' --tlsv1.2 -w '%{http_code}' -o "$TMPDIR_RELEASE/release.json" "$api" 2>/dev/null) || http="000"
case "$http" in
  200) ;;
  000) die "Could not reach GitHub. Are you online?" ;;
  403) die "GitHub rate-limited this request. Wait a few minutes and try again." ;;
  404) die "No releases published for $REPO yet. Build from source instead — see the README." ;;
  *)   die "GitHub returned HTTP $http for $api." ;;
esac
release=$(cat "$TMPDIR_RELEASE/release.json")

tag=$(printf '%s' "$release" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$tag" ] || die "No published release found. Build from source instead — see the README."

url=$(printf '%s' "$release" \
  | sed -n 's/.*"browser_download_url": *"\([^"]*TabSwitcher[^"]*\.zip\)".*/\1/p' | head -1)
[ -n "$url" ] || die "Release $tag has no TabSwitcher zip attached."

sums_url=$(printf '%s' "$release" \
  | sed -n 's/.*"browser_download_url": *"\([^"]*checksums\.txt\)".*/\1/p' | head -1)

# --- download ----------------------------------------------------------------------

say "Downloading $tag"
curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$tmp/app.zip" || die "Download failed."

actual=$(shasum -a 256 "$tmp/app.zip" | cut -d' ' -f1)
say "SHA-256: $actual"

if [ -n "$sums_url" ]; then
  curl -fsSL --proto '=https' --tlsv1.2 "$sums_url" -o "$tmp/checksums.txt" \
    || die "Could not fetch checksums.txt."
  expected=$(grep -i "$(basename "$url")" "$tmp/checksums.txt" | cut -d' ' -f1 | head -1)
  [ -n "$expected" ] || die "checksums.txt does not list $(basename "$url")."
  [ "$actual" = "$expected" ] || die "Checksum mismatch. Expected $expected. Not installing."
  say "Checksum verified against the release."
else
  # Said out loud rather than passed over: without a published list there is nothing to
  # compare against, and a checksum you cannot check is decoration.
  warn "This release publishes no checksums.txt, so the hash above verifies nothing."
  warn "Compare it against the release page yourself if that matters to you."
fi

# --- install -----------------------------------------------------------------------

say "Unpacking"
ditto -x -k "$tmp/app.zip" "$tmp/unpacked" || die "Could not unpack the archive."
[ -d "$tmp/unpacked/$APP" ] || die "The archive does not contain $APP."

if pgrep -f "$DEST/$APP" >/dev/null 2>&1 || pgrep -x TabSwitcher >/dev/null 2>&1; then
  say "Quitting the running copy"
  osascript -e 'tell application "TabSwitcher" to quit' >/dev/null 2>&1 || pkill -x TabSwitcher || true
  sleep 1
fi

# Replaces the bundle rather than merging into it: a leftover file from an older version
# invalidates the signature, and an invalid signature loses every granted permission.
if [ -d "$DEST/$APP" ]; then
  say "Replacing the existing install at $DEST/$APP"
  rm -rf "$DEST/$APP"
fi
ditto "$tmp/unpacked/$APP" "$DEST/$APP" || die "Could not install to $DEST."

# curl does not set com.apple.quarantine, so there should be nothing here. Checked
# rather than assumed, because a stale attribute produces a confusing Gatekeeper dialog
# and an unhelpful bug report.
if xattr -p com.apple.quarantine "$DEST/$APP" >/dev/null 2>&1; then
  warn "The bundle carries a quarantine attribute. macOS will ask you to confirm it on launch."
fi

say "Installed $tag to $DEST/$APP"
echo
echo "  Launch it:    open '$DEST/$APP'"
echo "  Then:         grant Accessibility and Screen Recording when asked — the app"
echo "                explains what each is for before prompting."
echo "  Switch:       hold ⌥ and press Tab"
echo "  Quit:         menu bar icon → Quit"
echo
echo "  Uninstall:    rm -rf '$DEST/$APP' ~/Library/Caches/$BUNDLE_ID"
echo "                and remove it from System Settings → Privacy & Security"
