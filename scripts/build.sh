#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/Breaking the Pattern.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$ROOT_DIR/src/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/src/"*.icns "$APP_BUNDLE/Contents/Resources/"
cp "$ROOT_DIR/src/AppIcon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
if [ -f "$ROOT_DIR/bin/unshield" ]; then
    cp "$ROOT_DIR/bin/unshield" "$APP_BUNDLE/Contents/Resources/unshield"
    chmod 755 "$APP_BUNDLE/Contents/Resources/unshield"
fi

for SCRIPT in break-gtasa.sh break-codbo.sh break-codbo2.sh break-game.sh btp-peinfo.py btp-make-icon.swift; do
    if [ -f "$ROOT_DIR/scripts/$SCRIPT" ]; then
        cp "$ROOT_DIR/scripts/$SCRIPT" "$APP_BUNDLE/Contents/Resources/$SCRIPT"
        chmod 755 "$APP_BUNDLE/Contents/Resources/$SCRIPT"
    fi
done

# Launcher genérico usado pelos apps que o break-game.sh gera
xcrun swiftc -O -target arm64-apple-macos14.0 \
  "$ROOT_DIR/src/BTPGameLauncher.swift" \
  -o "$APP_BUNDLE/Contents/Resources/BTPGameLauncher"

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

# Deploy to local Applications and Apps criados
mkdir -p "$HOME/Applications" "$HOME/Movies/Apps criados"
cp -Rf "$APP_BUNDLE" "$HOME/Applications/"
cp -Rf "$APP_BUNDLE" "$HOME/Movies/Apps criados/"

printf 'Build concluído, assinado e instalado em:\n - %s\n - %s\n' \
    "$HOME/Applications/Breaking the Pattern.app" \
    "$HOME/Movies/Apps criados/Breaking the Pattern.app"
