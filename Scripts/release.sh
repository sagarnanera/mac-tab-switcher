#!/bin/bash
#
# Packages a release: Release build, zipped, with a checksum list the installer verifies.
#
#   bash Scripts/release.sh            # package whatever MARKETING_VERSION says
#
# Produces dist/TabSwitcher-<version>.zip and dist/checksums.txt. Uploading them is a
# separate, deliberate step — see the end of this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST="$ROOT/dist"
DERIVED="$ROOT/.build/xcode-release"

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' TabSwitcher.xcodeproj/project.pbxproj | head -1)
[ -n "$VERSION" ] || { echo "error: could not read MARKETING_VERSION" >&2; exit 1; }

# A release built from a dirty tree cannot be reproduced from the tag it claims to be.
if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is dirty. Commit or stash before packaging a release." >&2
    git status --short >&2
    exit 1
fi

echo "==> Testing"
( cd Packages/SwitcherCore && swift test >/dev/null )

echo "==> Building $VERSION (Release)"
rm -rf "$DERIVED"
xcodebuild -project TabSwitcher.xcodeproj -scheme TabSwitcher \
    -configuration Release -derivedDataPath "$DERIVED" build \
    | grep -E 'error:|BUILD' || true

APP="$DERIVED/Build/Products/Release/TabSwitcher.app"
[ -d "$APP" ] || { echo "error: no app bundle at $APP" >&2; exit 1; }

echo "==> Verifying the signature"
codesign --verify --deep --strict "$APP" || {
    echo "error: the bundle does not pass its own signature check." >&2
    exit 1
}
codesign -d -r- "$APP" 2>&1 | grep designated | sed 's/^/    /'

rm -rf "$DIST"
mkdir -p "$DIST"
ZIP="$DIST/TabSwitcher-$VERSION.zip"

# ditto, not zip: it preserves the resource forks and extended attributes a signed
# bundle needs. A plain `zip` produces an archive whose signature no longer verifies.
echo "==> Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

( cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > checksums.txt )

# --- Sparkle ------------------------------------------------------------------------

SIGN_UPDATE=$(find "$DERIVED/SourcePackages/artifacts" -name sign_update -type f 2>/dev/null | head -1)
if [ -z "$SIGN_UPDATE" ]; then
    echo "error: sign_update not found. Resolve packages first (build once in Xcode)." >&2
    exit 1
fi

echo "==> Signing the update for Sparkle"
# Fails loudly rather than emitting an unsigned entry. An appcast item whose signature
# is missing is rejected by every client, so a silent skip here would ship a release
# that cannot be installed and would look like a Sparkle bug months later.
SIGNATURE=$("$SIGN_UPDATE" "$ZIP") || {
    echo "error: sign_update failed. Is the EdDSA private key in this machine's keychain?" >&2
    echo "       It was created by Sparkle's generate_keys and is NOT in the repository." >&2
    exit 1
}

LENGTH=$(stat -f%z "$ZIP")
PUBDATE=$(date -R 2>/dev/null || date "+%a, %d %b %Y %H:%M:%S %z")
URL="https://github.com/$( sed -n 's/.*"github_repo": *"\([^"]*\)".*/\1/p' .release.json 2>/dev/null || echo sagarnanera/tab-switcher )/releases/download/v$VERSION/$(basename "$ZIP")"

# Written to dist/ rather than straight into docs/appcast.xml: publishing an appcast
# entry is what actually offers the update to every existing install, and that should be
# a deliberate paste after the release exists, not a side effect of building one.
cat > "$DIST/appcast-item.xml" <<XML
        <item>
            <title>$VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:releaseNotesLink>https://github.com/sagarnanera/tab-switcher/blob/main/CHANGELOG.md</sparkle:releaseNotesLink>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" $SIGNATURE />
        </item>
XML

echo ""
echo "    $(cat "$DIST/checksums.txt")"
echo ""
echo "==> Built $ZIP"
echo ""
echo "    This build is NOT notarized. A browser download of it will be blocked by"
echo "    Gatekeeper; Scripts/install.sh is the path that works."
echo ""
echo "    To publish, deliberately, in this order:"
echo "      1. git tag v$VERSION && git push origin v$VERSION"
echo "      2. gh release create v$VERSION '$ZIP' '$DIST/checksums.txt' --title v$VERSION"
echo "      3. paste dist/appcast-item.xml as the FIRST <item> in docs/appcast.xml, commit, push"
echo ""
echo "    Step 3 last, and only once step 2 has succeeded. The appcast is what offers the"
echo "    update to every existing install; publishing it before the download exists"
echo "    points every user at a 404."
