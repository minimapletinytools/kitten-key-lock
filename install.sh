#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PoohBooLock"
./build.sh

SOURCE="dist/${APP_NAME}.app"

if [ -w /Applications ]; then
    TARGET="/Applications/${APP_NAME}.app"
else
    TARGET="$HOME/Applications/${APP_NAME}.app"
    mkdir -p "$HOME/Applications"
fi

echo "==> Unlocking and quitting any running copy"
if [ -x "$TARGET/Contents/MacOS/${APP_NAME}" ]; then
    "$TARGET/Contents/MacOS/${APP_NAME}" --unlock >/dev/null 2>&1 || true
fi
"$SOURCE/Contents/MacOS/${APP_NAME}" --unlock >/dev/null 2>&1 || true
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

echo "==> Installing to $TARGET"
rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "==> Launching"
open "$TARGET"

echo
echo "PoohBooLock is in your menu bar (pawprint icon)."
echo "Choose Lock Built-in Keyboard Only or Lock All Keyboards from the menu."
echo "Unlock by pressing C, A and T (all-keyboards mode: either keyboard), or from the menu."
