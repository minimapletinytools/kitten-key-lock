#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PoohBooLock"
FOUND=""
for candidate in "/Applications/${APP_NAME}.app" "$HOME/Applications/${APP_NAME}.app"; do
    if [ -d "$candidate" ]; then
        FOUND="$candidate"
        break
    fi
done

if [ -n "$FOUND" ]; then
    echo "==> Unlocking"
    "$FOUND/Contents/MacOS/${APP_NAME}" --unlock >/dev/null 2>&1 || true

    echo "==> Removing PoohBooLock rule from Karabiner"
    "$FOUND/Contents/MacOS/${APP_NAME}" --remove-rule \
        || echo "warning: could not remove the Karabiner rule (is Karabiner-Elements running?)"
fi

echo "==> Quitting app"
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Removing login item"
launchctl bootout "gui/$(id -u)/com.giraffe.pooboolock.login" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.giraffe.pooboolock.login.plist"

if [ -n "$FOUND" ]; then
    echo "==> Removing $FOUND"
    rm -rf "$FOUND"
fi

defaults delete com.giraffe.pooboolock 2>/dev/null || true

echo
echo "Done. Karabiner configuration backups and logs were kept in:"
echo "  $HOME/Library/Application Support/PoohBooLock"
echo "Delete that folder too if you want a completely clean removal."
