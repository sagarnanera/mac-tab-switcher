#!/bin/bash
# Quits TabSwitcher.
#
# Exists because an agent app has no Dock icon and its menu bar item can end up
# unreachable — pushed under the notch on a crowded menu bar, for instance. A
# switcher you cannot quit is worse than one that does not run.
set -euo pipefail
if pkill -f 'TabSwitcher.app/Contents/MacOS/TabSwitcher' 2>/dev/null; then
    echo "TabSwitcher quit"
else
    echo "TabSwitcher was not running"
fi
