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

echo ""
echo "    $(cat "$DIST/checksums.txt")"
echo ""
echo "==> Built $ZIP"
echo ""
echo "    This build is NOT notarized. A browser download of it will be blocked by"
echo "    Gatekeeper; Scripts/install.sh is the path that works."
echo ""
echo "    To publish, deliberately:"
echo "      git tag v$VERSION && git push origin v$VERSION"
echo "      gh release create v$VERSION '$ZIP' '$DIST/checksums.txt' --title v$VERSION"
