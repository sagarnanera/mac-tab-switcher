#!/bin/bash
# Clears TabSwitcher's TCC grants so the next launch starts from a clean slate.
#
# Needed when the app's signature or install path has changed: macOS then holds a
# record that no longer matches, which shows as "granted" in System Settings while
# every call fails. Resetting is the only way to get the prompts back.
set -euo pipefail
BUNDLE_ID="dev.nanera.tabswitcher"

pkill -f 'TabSwitcher.app' 2>/dev/null || true
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true

echo "cleared Accessibility, Screen Recording and Input Monitoring for $BUNDLE_ID"
echo ""
echo "If stale rows remain in System Settings, remove them by hand:"
echo "  Privacy & Security > Accessibility            → remove any TabSwitcher row"
echo "  Privacy & Security > Screen & System Audio Recording → remove any TabSwitcher row"
