#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PoohBooLock"
BUNDLE="dist/${APP_NAME}.app"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCHS=(arm64 x86_64)
else
    ARCHS=("$(uname -m)")
fi

echo "==> Building ${APP_NAME} for ${ARCHS[*]}"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" build

if [ ! -f AppIcon.icns ]; then
    echo "==> Rendering app icon"
    rm -rf build/AppIcon.iconset
    mkdir -p build/AppIcon.iconset
    swift Tools/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
fi

SOURCES=(
    Sources/Utilities.swift
    Sources/LockMode.swift
    Sources/KarabinerConfig.swift
    Sources/GlobalHotKey.swift
    Sources/LoginItem.swift
    Sources/HUD.swift
    Sources/AppDelegate.swift
    Sources/main.swift
)

BINARIES=()
for arch in "${ARCHS[@]}"; do
    echo "==> Compiling for ${arch}"
    output="build/${APP_NAME}-${arch}"
    swiftc -O -whole-module-optimization -swift-version 5 \
        -target "${arch}-apple-macos13.0" \
        "${SOURCES[@]}" \
        -o "$output"
    BINARIES+=("$output")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$BUNDLE/Contents/MacOS/${APP_NAME}"
else
    lipo -create "${BINARIES[@]}" -output "$BUNDLE/Contents/MacOS/${APP_NAME}"
fi

cp Info.plist "$BUNDLE/Contents/Info.plist"
cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

plutil -lint "$BUNDLE/Contents/Info.plist" >/dev/null

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$BUNDLE" >/dev/null
codesign --verify --verbose=2 "$BUNDLE" 2>&1 | tail -2

if [ "${#BINARIES[@]}" -gt 1 ]; then
    echo "==> Universal binary"
    lipo -info "$BUNDLE/Contents/MacOS/${APP_NAME}"
fi

echo "==> Built $BUNDLE"
