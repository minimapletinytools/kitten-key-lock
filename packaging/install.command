#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/PoohBooLock.app"

if [ ! -d "$APP" ]; then
    echo "PoohBooLock.app was not found next to install.command."
    echo "Unzip the whole release archive first, then run this again."
    read -r -p "Press Return to close..." _ || true
    exit 1
fi

echo "Clearing the macOS quarantine flag (this release is ad-hoc signed, not notarized)..."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if [ -w /Applications ]; then
    TARGET="/Applications/PoohBooLock.app"
else
    TARGET="$HOME/Applications/PoohBooLock.app"
    mkdir -p "$HOME/Applications"
fi

if [ -x "$TARGET/Contents/MacOS/PoohBooLock" ]; then
    echo "Unlocking the existing copy (if needed)..."
    "$TARGET/Contents/MacOS/PoohBooLock" --unlock >/dev/null 2>&1 || true
fi

echo "Installing to $TARGET ..."
pkill -x PoohBooLock 2>/dev/null || true
sleep 0.3
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
open "$TARGET"

echo
echo "PoohBooLock is in your menu bar (pawprint icon)."
echo "Karabiner-Elements must be installed and running."
echo
read -r -p "Press Return to close..." _ || true
