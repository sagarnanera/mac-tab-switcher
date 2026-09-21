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

# Installs to a stable path, updating in place rather than deleting and recopying.
# Replacing the bundle wholesale gives it a new inode every build, which churns the
# TCC records keyed to it — the permissions then appear granted while doing nothing.
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/TabSwitcher.app"
mkdir -p "$INSTALL_DIR"
rsync -a --delete "$DERIVED/Build/Products/$CONFIG/TabSwitcher.app/" "$APP/"

echo ""
echo "installed: $APP"
echo "designated requirement (identical across builds ⇒ TCC grants survive):"
codesign -d -r- "$APP" 2>&1 | grep designated | sed 's/^/  /'

if [[ "${1:-}" == "--run" ]]; then
    pkill -f 'TabSwitcher.app' 2>/dev/null || true
    sleep 1
    open "$APP"
fi
