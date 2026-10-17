#!/bin/bash
# BREAK genérico: transforma qualquer pasta de jogo Windows em um .app nativo do macOS.
#
# Uso:
#   break-game.sh --title "Nome do Jogo" --game-dir /caminho/da/pasta --exe sub/pasta/jogo.exe \
#                 [--icon arte.ico|png|icns] [--renderer auto|d3d9=mtld3d|dxgi=dxmt|dxgi=gptk|wined3d] \
#                 [--args "-argumentos do jogo"] [--overrides "dll=n,b;..."] [--link]
#
# --exe é relativo a --game-dir. Por padrão a pasta do jogo é clonada (APFS, sem ocupar espaço
# extra no mesmo volume) para dentro do prefixo, então o .app não depende mais da pasta original.
# --link usa um link simbólico no lugar do clone.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DONOR_RESOURCES="${BTP_DONOR_RESOURCES:-$HOME/Applications/Need for Speed Underground 2.app/Contents/Resources}"
APPS_DIR="${BTP_APPS_DIR:-$HOME/Applications}"

TITLE="" GAME_DIR="" EXE="" ICON="" RENDERER="auto" WINVER="auto" GAME_ARGS="" OVERRIDES="dinput8=n,b;winemenubuilder.exe=" LINK=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="$2"; shift 2 ;;
        --game-dir) GAME_DIR="$2"; shift 2 ;;
        --exe) EXE="$2"; shift 2 ;;
        --icon) ICON="$2"; shift 2 ;;
        --renderer) RENDERER="$2"; shift 2 ;;
        --winver) WINVER="$2"; shift 2 ;;
        --args) GAME_ARGS="$2"; shift 2 ;;
        --overrides) OVERRIDES="$2"; shift 2 ;;
        --link) LINK=1; shift ;;
        *) echo "Opção desconhecida: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$TITLE" && -n "$GAME_DIR" && -n "$EXE" ]] || { echo "Faltam --title, --game-dir ou --exe" >&2; exit 2; }
GAME_DIR="$(cd "$GAME_DIR" && pwd)"
[[ -f "$GAME_DIR/$EXE" ]] || { echo "Executável não encontrado: $GAME_DIR/$EXE" >&2; exit 1; }
[[ -d "$DONOR_RESOURCES/GameRuntime.app" ]] || { echo "Runtime não encontrado em $DONOR_RESOURCES" >&2; exit 1; }

# Identificadores derivados do título: "Max Payne 2" -> max-payne-2 / MaxPayne2
SLUG="$(printf '%s' "$TITLE" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
SLUG="${SLUG:-jogo}"
FOLDER_ID="$(printf '%s' "$TITLE" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | sed -E 's/[^A-Za-z0-9]//g')"
FOLDER_ID="${FOLDER_ID:-Game}"
DATA_DIR="$HOME/Library/Application Support/$TITLE"
TARGET_APP="$APPS_DIR/$TITLE.app"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/btp-break.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "[1/5] Analisando o executável $(basename "$EXE")..."
INFO="$(python3 -I "$SCRIPT_DIR/btp-peinfo.py" "$GAME_DIR/$EXE" --icon "$WORK/exe.ico")"
ARCH="$(printf '%s' "$INFO" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["arch"])')"
if [[ "$RENDERER" == "auto" ]]; then
    RENDERER="$(printf '%s' "$INFO" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["renderer"])')"
fi
[[ "$RENDERER" == "wined3d" ]] && RENDERER=""
if [[ "$RENDERER" == "dxgi=gptk" && "$ARCH" != "x64" ]]; then
    RENDERER="dxgi=dxmt"   # o backend D3DMetal só existe em 64 bits
fi
YEAR="$(printf '%s' "$INFO" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("year", 0))')"
# Jogos anteriores a 2012 só conhecem até o Windows 7; alguns (ex.: Splinter Cell Conviction)
# recusam abrir com "Operating System not supported" se o Wine se apresenta como Windows 10.
if [[ "$WINVER" == "auto" ]]; then
    if [[ "$YEAR" -gt 0 && "$YEAR" -lt 2012 ]]; then WINVER="win7"; else WINVER=""; fi
fi
echo "      Arquitetura: $ARCH | Compilado em: ${YEAR/#0/?} | Motor gráfico: ${RENDERER:-WineD3D padrão} | Windows: ${WINVER:-padrão (10)}"

echo "[2/5] Gerando ícone do aplicativo..."
ICON_SRC="$ICON"
if [[ -z "$ICON_SRC" && -s "$WORK/exe.ico" ]]; then ICON_SRC="$WORK/exe.ico"; fi
if [[ -n "$ICON_SRC" && "$ICON_SRC" == *.icns ]]; then
    cp "$ICON_SRC" "$WORK/GameIcon.icns"
else
    if [[ -z "$ICON_SRC" ]] || ! xcrun swift "$SCRIPT_DIR/btp-make-icon.swift" "$ICON_SRC" "$WORK/base.png" 2>/dev/null; then
        cp "$ROOT_DIR/src/AppIcon.png" "$WORK/base.png" 2>/dev/null || cp "$SCRIPT_DIR/AppIcon.png" "$WORK/base.png"
    fi
    mkdir -p "$WORK/GameIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$WORK/base.png" --out "$WORK/GameIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$WORK/base.png" --out "$WORK/GameIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$WORK/GameIcon.iconset" -o "$WORK/GameIcon.icns"
fi

echo "[3/5] Preparando o prefixo Wine (Zero-Clutter APFS Storage Engine)..."
mkdir -p "$DATA_DIR/Registros"
if [[ ! -d "$DATA_DIR/prefix-metal" ]]; then
    cp -Rc "$DONOR_RESOURCES/PrefixSeed" "$DATA_DIR/prefix-metal"
fi
mkdir -p "$DATA_DIR/prefix-metal/dosdevices" "$DATA_DIR/prefix-metal/drive_c/Games"
ln -sfn "/" "$DATA_DIR/prefix-metal/dosdevices/z:"
DRIVE_C="$(cd "$DATA_DIR/prefix-metal/drive_c" && pwd)"
if [[ "$GAME_DIR" == "$DRIVE_C"/* ]]; then
    # Jogo instalado pelo install-game.sh: já está no prefixo, roda de onde o instalador pôs
    # (o registro do Windows aponta para lá).
    GAME_REL="${GAME_DIR#"$DRIVE_C"/}"
    GAME_IN_PREFIX="$GAME_DIR"
    echo "      Jogo instalado no prefixo: C:\\$(printf '%s' "$GAME_REL" | tr '/' '\\')"
else
    GAME_REL="Games/$FOLDER_ID"
    GAME_IN_PREFIX="$DRIVE_C/$GAME_REL"
fi
if [[ "$GAME_IN_PREFIX" == "$GAME_DIR" ]]; then
    :
elif [[ "$LINK" == 1 ]]; then
    ln -sfn "$GAME_DIR" "$GAME_IN_PREFIX"
elif [[ -L "$GAME_IN_PREFIX" || ! -e "$GAME_IN_PREFIX" ]]; then
    rm -f "$GAME_IN_PREFIX"
    # Clone APFS; se a origem estiver em outro volume, cai para cópia normal.
    cp -Rc "$GAME_DIR" "$GAME_IN_PREFIX" 2>/dev/null || { rm -rf "$GAME_IN_PREFIX"; cp -R "$GAME_DIR" "$GAME_IN_PREFIX"; }
else
    echo "      Jogo já instalado no prefixo; mantendo arquivos e saves existentes."
fi
if [[ -n "$WINVER" ]]; then
    # Versão do Windows só para este .exe (AppDefaults), sem mexer no resto do prefixo.
    WINEPREFIX="$DATA_DIR/prefix-metal" WINEARCH=wow64 WINELOADERNOEXEC=1 WINEDEBUG=-all \
    WINESERVER="$DONOR_RESOURCES/wine/bin/wineserver" \
        "$DONOR_RESOURCES/GameRuntime.app/Contents/MacOS/wine" reg add \
        "HKCU\\Software\\Wine\\AppDefaults\\$(basename "$EXE")" /v Version /t REG_SZ /d "$WINVER" /f >/dev/null 2>&1 || true
    WINEPREFIX="$DATA_DIR/prefix-metal" "$DONOR_RESOURCES/wine/bin/wineserver" -w 2>/dev/null || true
fi
cat > "$GAME_IN_PREFIX/mtld3d.conf" << 'EOF'
shader.asyncCompile = true
depth.aliasSameSize = false
present.maxFps = 0
present.maxFrameLatency = 1
query.flushImmediate = true
query.eventImmediate = true
EOF

echo "[4/5] Montando $TITLE.app com o BTP HyperMetal Engine..."
rm -rf "$TARGET_APP"
mkdir -p "$TARGET_APP/Contents/MacOS" "$TARGET_APP/Contents/Resources"
cp "$WORK/GameIcon.icns" "$TARGET_APP/Contents/Resources/GameIcon.icns"
cp -Rc "$DONOR_RESOURCES/GameRuntime.app" "$TARGET_APP/Contents/Resources/GameRuntime.app"
cp -Rc "$DONOR_RESOURCES/Underground 2 FPS.app" "$TARGET_APP/Contents/Resources/Underground 2 FPS.app"
cp -f "$DONOR_RESOURCES/RuntimeBootstrap" "$TARGET_APP/Contents/Resources/RuntimeBootstrap"
cp -f "$DONOR_RESOURCES/x87sidecar" "$TARGET_APP/Contents/Resources/x87sidecar"
ln -sfn "GameRuntime.app/Contents/Resources/wine" "$TARGET_APP/Contents/Resources/wine"

# Valores escritos com %q para sobreviver a espaços, aspas e barras invertidas no launch-game.sh.
EXE_WIN="C:\\$(printf '%s' "$GAME_REL/$EXE" | tr '/' '\\')"
EXE_DIR_REL="$(dirname "$EXE")"
X87_LINE=""
[[ "$ARCH" == "i386" ]] && X87_LINE='export ROSETTA_X87_PATH="$RESOURCES/x87sidecar"'
COMPAT=$'v=5\nname='"$SLUG"';exe='"$(basename "$EXE")"
[[ -n "$RENDERER" ]] && COMPAT+=";$RENDERER"
{
    echo '#!/bin/bash'
    echo 'set -eu'
    echo 'RESOURCES="$1"'
    echo 'DATA="$2"'
    printf 'GAME_SUBDIR=%q\n' "$GAME_REL/$EXE_DIR_REL"
    printf 'EXE_WIN=%q\n' "$EXE_WIN"
    printf 'GAME_ARGS=(%s)\n' "$GAME_ARGS"
    printf 'export WINEDLLOVERRIDES=%q\n' "$OVERRIDES"
    printf 'export WINE_COMPATDB=%q\n' "$COMPAT"
    printf 'TITLE=%q\n' "$TITLE"
    echo "$X87_LINE"
    cat << 'EOF'
WINE="$RESOURCES/GameRuntime.app/Contents/MacOS/wine"
HUD="$RESOURCES/Underground 2 FPS.app/Contents/MacOS/Underground2FPS"
LOG=$(mktemp "$DATA/Registros/game-$(date +%Y%m%d-%H%M%S)-XXXXXX")
HUD_PID=""
cleanup() {
    if [[ -n "$HUD_PID" ]]; then kill "$HUD_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
ulimit -s 65520
ulimit -n 1048575
export MallocNanoZone=0 LC_ALL=C.UTF-8 LANG=C.UTF-8
cd "$DATA/prefix-metal/drive_c/$GAME_SUBDIR"
export PATH="$RESOURCES/wine/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export WINEPREFIX="$DATA/prefix-metal"
export WINESERVER="$RESOURCES/wine/bin/wineserver"
export WINEARCH=wow64 WINELOADERNOEXEC=1
export X87_SAMPLE="$DATA/Registros/x87-profile" X87_SAMPLE_HZ=500 X87_SAMPLE_REPORT=5
export WINEDEBUG=-all,+fps,+timestamp
export MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 MTL_HUD_OPACITY=0
printf 'Abrindo BTP HyperMetal Engine (%s). Registro: %s\n' "$TITLE" "$LOG"
PIDFILE="$LOG.pid"
"$RESOURCES/RuntimeBootstrap" "$PIDFILE" "$RESOURCES/x87sidecar" --cooperative "$WINE" "$EXE_WIN" ${GAME_ARGS[@]+"${GAME_ARGS[@]}"} > "$LOG" 2>&1 &
BOOT_PID=$!
for i in {1..100}; do [[ -s "$PIDFILE" ]] && break; sleep 0.05; done
GAME_PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
if [[ -n "$GAME_PID" ]]; then
    printf '%s\n' "$GAME_PID" > "$DATA/Registros/game.pid"
    # Espera o Metal criar a superfície do jogo antes de abrir o painel de FPS.
    for i in {1..90}; do
        kill -0 "$GAME_PID" 2>/dev/null || break
        if /usr/bin/grep -q '\[libMTLHud\]\|metal-HUD:' "$LOG"; then break; fi
        sleep 1
    done
    "$HUD" --log "$LOG" --parent-pid "$GAME_PID" --diagnostics "$LOG.fps-panel.log" > "$LOG.fps-panel-errors.log" 2>&1 &
    HUD_PID=$!
fi
wait "$BOOT_PID"
EOF
} > "$TARGET_APP/Contents/Resources/launch-game.sh"
chmod 755 "$TARGET_APP/Contents/Resources/launch-game.sh"

plist() { /usr/libexec/PlistBuddy -c "$1" "$TARGET_APP/Contents/Info.plist" >/dev/null; }
plist "Add :CFBundleDisplayName string $TITLE"
plist "Add :CFBundleName string $TITLE"
plist "Add :CFBundleExecutable string BTPGame"
plist "Add :CFBundleIconFile string GameIcon"
plist "Add :CFBundleIdentifier string org.lendaii.btp.$SLUG"
plist "Add :CFBundlePackageType string APPL"
plist "Add :CFBundleShortVersionString string 1.0"
plist "Add :CFBundleVersion string 1"
plist "Add :LSMinimumSystemVersion string 14.0"
plist "Add :NSHighResolutionCapable bool true"
plist "Add :NSPrincipalClass string NSApplication"
plist "Add :BTPDataFolder string $TITLE"
plist "Add :BTPExecutable string $EXE"
plist "Add :BTPRenderer string ${RENDERER:-wined3d}"

# Launcher pré-compilado pelo build.sh; se não houver, compila na hora.
if [[ -x "$SCRIPT_DIR/BTPGameLauncher" ]]; then
    cp "$SCRIPT_DIR/BTPGameLauncher" "$TARGET_APP/Contents/MacOS/BTPGame"
else
    LAUNCHER_SRC="$ROOT_DIR/src/BTPGameLauncher.swift"
    [[ -f "$LAUNCHER_SRC" ]] || LAUNCHER_SRC="$SCRIPT_DIR/BTPGameLauncher.swift"
    xcrun swiftc -O -target arm64-apple-macos14.0 "$LAUNCHER_SRC" -o "$TARGET_APP/Contents/MacOS/BTPGame"
fi
chmod 755 "$TARGET_APP/Contents/MacOS/BTPGame"

echo "[5/5] Assinando o aplicativo..."
for ATTR in com.apple.FinderInfo com.apple.ResourceFork; do
    xattr -r -d "$ATTR" "$TARGET_APP" 2>/dev/null || true
done
codesign --force --deep --sign - "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
echo "✅ App nativo criado com sucesso: $TARGET_APP"
