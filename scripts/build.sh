#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/Breaking the Pattern.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$ROOT_DIR/src/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/src/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/src/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
if [ -f "$ROOT_DIR/bin/unshield" ]; then
    cp "$ROOT_DIR/bin/unshield" "$APP_BUNDLE/Contents/Resources/unshield"
    chmod 755 "$APP_BUNDLE/Contents/Resources/unshield"
fi

xcrun swiftc -O -target arm64-apple-macos14.0 \
  "$ROOT_DIR/src/BreakingThePattern.swift" \
  -o "$APP_BUNDLE/Contents/MacOS/BreakingThePattern"

chmod 755 "$APP_BUNDLE/Contents/MacOS/BreakingThePattern"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

for ATTR in com.apple.FinderInfo com.apple.ResourceFork; do
    xattr -r -d "$ATTR" "$APP_BUNDLE" 2>/dev/null || true
done

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

printf 'Build concluído e verificado: %s\n' "$APP_BUNDLE"
