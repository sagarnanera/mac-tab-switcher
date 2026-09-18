#!/bin/bash
# Builds TabSwitcher.app from the SPM executable.
#
# SPM cannot emit a .app, and macOS will not grant TCC permissions to a bare
# executable, so the bundle is assembled here: Info.plist for identity, entitlements
# for the hardened runtime, and a stable signature so permission grants survive
# rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
IDENTITY="${TABSWITCHER_SIGN_IDENTITY:-TabSwitcher Dev}"
APP="$ROOT/build/TabSwitcher.app"
BUNDLE_ID="dev.nanera.tabswitcher"

cd "$ROOT"
swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/tabswitcher"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/TabSwitcher"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>TabSwitcher</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>TabSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

cat > "$ROOT/build/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><false/>
</dict>
</plist>
EOF

# Note: `find-identity -v` is deliberately NOT used. A self-signed identity reports
# CSSMERR_TP_NOT_TRUSTED and is filtered out by -v, but signs perfectly well — TCC
# keys grants on the code signature and its designated requirement, not on whether
# the chain is trusted. Trust only matters to Gatekeeper, i.e. to distribution.
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --deep --options runtime \
        --entitlements "$ROOT/build/entitlements.plist" \
        --sign "$IDENTITY" "$APP"
    echo "signed with: $IDENTITY"
else
    echo "WARNING: identity '$IDENTITY' not found — falling back to ad-hoc." >&2
    echo "         TCC grants will be lost on every rebuild." >&2
    echo "         Fix: Scripts/make-signing-identity.sh" >&2
    codesign --force --deep --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/  /'
echo "built: $APP"
