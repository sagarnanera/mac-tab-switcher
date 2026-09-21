#!/bin/bash
# Builds and signs into build/TabSwitcher.app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"
cd "$ROOT"

DERIVED="$ROOT/.build/xcode"
xcodebuild -project TabSwitcher.xcodeproj -scheme TabSwitcher \
    -configuration "$CONFIG" -derivedDataPath "$DERIVED" build \
    | grep -E 'error:|warning:|BUILD' || true

mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/TabSwitcher.app"
cp -R "$DERIVED/Build/Products/$CONFIG/TabSwitcher.app" "$ROOT/build/"

echo ""
echo "designated requirement (must be identical across builds for TCC grants to survive):"
codesign -d -r- "$ROOT/build/TabSwitcher.app" 2>&1 | grep designated | sed 's/^/  /'

if [[ "${1:-}" == "--run" ]]; then
    open "$ROOT/build/TabSwitcher.app"
elif [[ "${1:-}" == "--diagnose" ]]; then
    "$ROOT/build/TabSwitcher.app/Contents/MacOS/TabSwitcher" --diagnose
fi
