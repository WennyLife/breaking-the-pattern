#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/Breaking the Pattern.app"
INSTALL=0
case "${1:---build-only}" in
    --build-only) ;;
    --install) INSTALL=1 ;;
    --help|-h)
        echo 'Uso: scripts/build.sh [--build-only | --install]'
        echo 'Padrão: compila e verifica em build/, sem alterar aplicativos instalados.'
        echo '--install: após validar, instala e publica no acervo central com backups.'
        exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Informe somente --build-only ou --install.' >&2; exit 2; }

mkdir -p "$BUILD_DIR"
STAGE_DIR="$(mktemp -d "$BUILD_DIR/.btp-build.XXXXXX")"
APP_STAGE="$STAGE_DIR/Breaking the Pattern.app"
PREVIOUS_BUILD=""
cleanup_build() {
    local result=$?
    if [[ -n "$PREVIOUS_BUILD" && ! -e "$APP_BUNDLE" && ! -L "$APP_BUNDLE" && -e "$PREVIOUS_BUILD" ]]; then
        mv "$PREVIOUS_BUILD" "$APP_BUNDLE" || { echo "Build anterior preservado em: $PREVIOUS_BUILD" >&2; result=1; }
    fi
    rm -rf "$STAGE_DIR"
    return "$result"
}
trap cleanup_build EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"

cp "$ROOT_DIR/src/Info.plist" "$APP_STAGE/Contents/Info.plist"
cp "$ROOT_DIR/src/"*.icns "$APP_STAGE/Contents/Resources/"
cp "$ROOT_DIR/src/AppIcon.png" "$APP_STAGE/Contents/Resources/AppIcon.png"
if [[ -f "$ROOT_DIR/bin/unshield" ]]; then
    cp "$ROOT_DIR/bin/unshield" "$APP_STAGE/Contents/Resources/unshield"
    chmod 755 "$APP_STAGE/Contents/Resources/unshield"
fi

# Lista explícita: não copie patches, executáveis de jogos, prefixos ou saves.
for SCRIPT in break-gtasa.sh break-game.sh btp-peinfo.py btp-make-icon.swift btp-splinter-profile.py btp-runtime.py runtime-manifest.json btp-game-profile.py game-profiles.json btp-clean-metadata.py; do
    if [[ -f "$ROOT_DIR/scripts/$SCRIPT" ]]; then
        cp "$ROOT_DIR/scripts/$SCRIPT" "$APP_STAGE/Contents/Resources/$SCRIPT"
        chmod 755 "$APP_STAGE/Contents/Resources/$SCRIPT"
    fi
done
cp "$ROOT_DIR/src/Localizations.json" "$APP_STAGE/Contents/Resources/"

mkdir -p "$APP_STAGE/Contents/Resources/RuntimeTools"
xcrun clang -O2 -arch arm64 "$ROOT_DIR/src/RuntimeBootstrap.c" -o "$APP_STAGE/Contents/Resources/RuntimeTools/RuntimeBootstrap"
xcrun swiftc -O -target arm64-apple-macos14.0 "$ROOT_DIR/src/FPSOverlay.swift" -o "$APP_STAGE/Contents/Resources/RuntimeTools/Underground2FPS"
xcrun swiftc -O -target arm64-apple-macos14.0 "$ROOT_DIR/scripts/btp-make-icon.swift" -o "$APP_STAGE/Contents/Resources/BTPMakeIcon"
python3 -I -B "$ROOT_DIR/scripts/btp-runtime.py" --stage-python "$APP_STAGE/Contents/Resources/Python"

SPARKLE_DIR="$STAGE_DIR/Sparkle"
python3 -I -B "$ROOT_DIR/scripts/btp-build-deps.py" "$SPARKLE_DIR"
mkdir -p "$APP_STAGE/Contents/Frameworks" "$APP_STAGE/Contents/Resources/Licenses"
/usr/bin/ditto --norsrc "$SPARKLE_DIR/Sparkle.framework" "$APP_STAGE/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$APP_STAGE/Contents/Resources/Licenses/Sparkle.txt"
/usr/bin/ditto --norsrc "$ROOT_DIR/licenses" "$APP_STAGE/Contents/Resources/Licenses/Components"

xcrun swiftc -O -target arm64-apple-macos14.0 \
  "$ROOT_DIR/src/BTPGameLauncher.swift" \
  -o "$APP_STAGE/Contents/Resources/BTPGameLauncher"
xcrun swiftc -O -target arm64-apple-macos14.0 \
  -F "$APP_STAGE/Contents/Frameworks" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$ROOT_DIR/src/BreakingThePattern.swift" "$ROOT_DIR/src/BTPUpdater.swift" "$ROOT_DIR/src/BTPUpdateBackup.swift" "$ROOT_DIR/src/BTPLanguage.swift" \
  -o "$APP_STAGE/Contents/MacOS/BreakingThePattern"
chmod 755 "$APP_STAGE/Contents/MacOS/BreakingThePattern"

python3 -I -B - "$ROOT_DIR" "$APP_STAGE" << 'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import sys

root, app = map(Path, sys.argv[1:])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
files = [p for folder in ('src', 'scripts', 'licenses') for p in (root / folder).rglob('*')
         if p.is_file() and '__pycache__' not in p.parts
         and p.name not in ('install-game.sh', 'btp-findinstalled.py')]
record = {
    'version': info['CFBundleShortVersionString'],
    'build': info['CFBundleVersion'],
    'built_at': datetime.now(timezone.utc).isoformat(),
    'source_sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)},
    'validation_scope': 'Build and package verification only. Game compatibility is validated separately.',
}
(app / 'Contents/Resources/Build.json').write_text(json.dumps(record, indent=2) + '\n')
PY

plutil -lint "$APP_STAGE/Contents/Info.plist"
for SCRIPT in "$APP_STAGE/Contents/Resources/"*.sh; do bash -n "$SCRIPT"; done
python3 -I -B "$ROOT_DIR/scripts/btp-clean-metadata.py" "$APP_STAGE"
codesign --force --deep --sign - "$APP_STAGE"
codesign --verify --deep --strict "$APP_STAGE"

# Troca somente após compilar, conferir sintaxe, assinar e verificar o pacote.
if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
    mkdir -p "$BUILD_DIR/Backups"
    PREVIOUS_DIR="$(mktemp -d "$BUILD_DIR/Backups/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
    PREVIOUS_BUILD="$PREVIOUS_DIR/Breaking the Pattern.app"
    mv "$APP_BUNDLE" "$PREVIOUS_BUILD"
fi
mv "$APP_STAGE" "$APP_BUNDLE"
printf 'Build concluído e verificado: %s\n' "$APP_BUNDLE"
if [[ -n "$PREVIOUS_BUILD" ]]; then printf 'Build anterior preservado: %s\n' "$PREVIOUS_BUILD"; fi

if [[ "$INSTALL" == 1 ]]; then
    python3 -I -B "$ROOT_DIR/scripts/publish-release.py" --app "$APP_BUNDLE" --project "$ROOT_DIR"
else
    echo 'Nenhum aplicativo instalado ou acervo foi alterado. Use --install para publicar.'
fi
