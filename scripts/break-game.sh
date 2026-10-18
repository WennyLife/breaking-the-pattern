#!/bin/bash
# BREAK genérico: prepara um launcher macOS para testar um jogo Windows com Wine.
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
if [[ -x "$SCRIPT_DIR/Python/bin/python3" ]]; then export PATH="$SCRIPT_DIR/Python/bin:$PATH"; fi
DONOR_RESOURCES="${BTP_RUNTIME_RESOURCES:-${BTP_DONOR_RESOURCES:-}}"
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
PROFILE_FOLDER=""
if [[ -f "$SCRIPT_DIR/btp-game-profile.py" ]]; then
    SETTINGS="$(python3 -I -B "$SCRIPT_DIR/btp-game-profile.py" --settings "$GAME_DIR/$EXE")"
    IFS='|' read -r PROFILE_FOLDER PROFILE_RENDERER PROFILE_WINVER <<< "$SETTINGS"
    if [[ -n "$PROFILE_FOLDER" ]]; then
        [[ "$RENDERER" != auto ]] || RENDERER="$PROFILE_RENDERER"
        [[ "$WINVER" != auto ]] || WINVER="$PROFILE_WINVER"
    fi
fi
if [[ -z "$DONOR_RESOURCES" ]]; then
    DONOR_RESOURCES="$(python3 -I -B "$SCRIPT_DIR/btp-runtime.py" --ensure)"
fi
[[ -d "$DONOR_RESOURCES/GameRuntime.app" ]] || { echo "Runtime não encontrado em $DONOR_RESOURCES" >&2; exit 1; }

# Identificadores derivados do título: "Max Payne 2" -> max-payne-2 / MaxPayne2
SLUG="$(printf '%s' "$TITLE" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
SLUG="${SLUG:-jogo}"
FOLDER_ID="$(printf '%s' "$TITLE" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | sed -E 's/[^A-Za-z0-9]//g')"
FOLDER_ID="${FOLDER_ID:-Game}"
if [[ -n "$PROFILE_FOLDER" ]]; then FOLDER_ID="$PROFILE_FOLDER"; fi
DATA_DIR="$HOME/Library/Application Support/$TITLE"
TARGET_APP="$APPS_DIR/$TITLE.app"
# Um jogo pode ser o próprio doador (NFSU2). Resolva links antes de qualquer
# criação/alteração para nunca substituir o runtime que ainda vamos copiar.
python3 -I -B - "$TARGET_APP" "$DONOR_RESOURCES" << 'PY'
from pathlib import Path
import sys

target, donor = (Path(value).resolve() for value in sys.argv[1:])
if target == donor or target in donor.parents or donor in target.parents:
    sys.exit("Destino e runtime doador se sobrepõem. O aplicativo atual foi preservado; escolha outro runtime doador.")
PY
WORK="$(mktemp -d "${TMPDIR:-/tmp}/btp-break.XXXXXX")"
APP_STAGE_DIR=""
BACKUP_APP=""
cleanup_build() {
    local result=$?
    # Se a troca falhar ou for interrompida após guardar a versão anterior,
    # restaure-a. O backup nunca é apagado como parte da limpeza temporária.
    if [[ -n "$BACKUP_APP" && ! -e "$TARGET_APP" && ! -L "$TARGET_APP" && ( -e "$BACKUP_APP" || -L "$BACKUP_APP" ) ]]; then
        mv "$BACKUP_APP" "$TARGET_APP" || { echo "Não foi possível restaurar o app. Backup: $BACKUP_APP" >&2; result=1; }
    fi
    rm -rf "$WORK"
    if [[ -n "$APP_STAGE_DIR" ]]; then rm -rf "$APP_STAGE_DIR"; fi
    return "$result"
}
trap cleanup_build EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$APPS_DIR"
# Mesmo volume do destino: a instalação final é uma renomeação do pacote pronto.
APP_STAGE_DIR="$(mktemp -d "$APPS_DIR/.btp-build.XXXXXX")"
APP_STAGE="$APP_STAGE_DIR/Game.app"

echo "[1/5] Analisando o executável $(basename "$EXE")..."
INFO="$(python3 -I -B "$SCRIPT_DIR/btp-peinfo.py" "$GAME_DIR/$EXE" --icon "$WORK/exe.ico")"
ARCH="$(printf '%s' "$INFO" | python3 -I -B -c 'import json,sys; print(json.load(sys.stdin)["arch"])')"
if [[ "$RENDERER" == "auto" ]]; then
    RENDERER="$(printf '%s' "$INFO" | python3 -I -B -c 'import json,sys; print(json.load(sys.stdin)["renderer"])')"
fi
[[ "$RENDERER" == "wined3d" ]] && RENDERER=""
if [[ "$RENDERER" == "dxgi=gptk" && "$ARCH" != "x64" ]]; then
    RENDERER="dxgi=dxmt"   # o backend D3DMetal só existe em 64 bits
fi
YEAR="$(printf '%s' "$INFO" | python3 -I -B -c 'import json,sys; print(json.load(sys.stdin).get("year", 0))')"
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
    ICON_COMMAND=(xcrun swift "$SCRIPT_DIR/btp-make-icon.swift")
    if [[ -x "$SCRIPT_DIR/BTPMakeIcon" ]]; then ICON_COMMAND=("$SCRIPT_DIR/BTPMakeIcon"); fi
    if [[ -z "$ICON_SRC" ]] || ! "${ICON_COMMAND[@]}" "$ICON_SRC" "$WORK/base.png" 2>/dev/null; then
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
    if [[ -d "$DONOR_RESOURCES/PrefixSeed" ]]; then
        cp -Rc "$DONOR_RESOURCES/PrefixSeed" "$DATA_DIR/prefix-metal"
    else
        python3 -I -B "$SCRIPT_DIR/btp-runtime.py" --init-prefix "$DATA_DIR/prefix-metal" --resources "$DONOR_RESOURCES"
    fi
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
    REG_LOG="$(mktemp "$DATA_DIR/Registros/config-windows-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
    if ! WINEPREFIX="$DATA_DIR/prefix-metal" WINEARCH=wow64 WINELOADERNOEXEC=1 WINEDEBUG=-all \
    WINESERVER="$DONOR_RESOURCES/wine/bin/wineserver" \
        python3 -I -B -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[1:], timeout=40).returncode)' \
        "$DONOR_RESOURCES/GameRuntime.app/Contents/MacOS/wine" reg add \
        "HKCU\\Software\\Wine\\AppDefaults\\$(basename "$EXE")" /v Version /t REG_SZ /d "$WINVER" /f >"$REG_LOG" 2>&1; then
        echo "Falha ao configurar $WINVER; app atual preservado. Registro: $REG_LOG" >&2
        exit 1
    fi
    if ! WINEPREFIX="$DATA_DIR/prefix-metal" python3 -I -B -c 'import subprocess,sys; sys.exit(subprocess.run(sys.argv[1:], timeout=40).returncode)' "$DONOR_RESOURCES/wine/bin/wineserver" -w >>"$REG_LOG" 2>&1; then
        echo "Falha ao concluir a configuração do Wine; app atual preservado. Registro: $REG_LOG" >&2
        exit 1
    fi
fi
[[ -f "$GAME_IN_PREFIX/$EXE" ]] || { echo "Executável não encontrado no prefixo: $GAME_IN_PREFIX/$EXE" >&2; exit 1; }
EXE_DIR_REL="$(dirname "$EXE")"
# O launcher usa a pasta do .exe como cwd, inclusive para executáveis aninhados.
# NFS uses the renderer defaults, matching the independently tested recipe.
# Preserve a configuration supplied by the user, but do not add the generic one.
if [[ "$PROFILE_FOLDER" != NFSU2 && ! -f "$GAME_IN_PREFIX/$EXE_DIR_REL/mtld3d.conf" ]]; then
cat > "$GAME_IN_PREFIX/$EXE_DIR_REL/mtld3d.conf" << 'EOF'
shader.asyncCompile = true
depth.aliasSameSize = false
present.maxFps = 0
present.maxFrameLatency = 1
query.flushImmediate = true
query.eventImmediate = true
EOF
fi

if [[ -f "$SCRIPT_DIR/btp-game-profile.py" ]]; then
    python3 -I -B "$SCRIPT_DIR/btp-game-profile.py" --game "$GAME_IN_PREFIX" --exe "$EXE" \
        --prefix "$DATA_DIR/prefix-metal" --resources "$DONOR_RESOURCES" --data "$DATA_DIR"
fi

# Receita específica reproduzida em cópia isolada. O helper aceita apenas a
# edição testada, baixa a correção oficial por checksum e guarda configurações.
if [[ "$(basename "$EXE" | tr '[:upper:]' '[:lower:]')" == "conviction_game.exe" ]]; then
    echo "[3/5] Preparando perfil experimental Conviction em janela..."
    python3 -I -B "$SCRIPT_DIR/btp-splinter-profile.py" \
        --game "$GAME_IN_PREFIX/$EXE_DIR_REL" --prefix "$DATA_DIR/prefix-metal" --data "$DATA_DIR"
    OVERRIDES+=";version=n,b"
fi

echo "[4/5] Montando $TITLE.app com o BTP HyperMetal Engine..."
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
cp "$WORK/GameIcon.icns" "$APP_STAGE/Contents/Resources/GameIcon.icns"
/usr/bin/ditto --norsrc "$DONOR_RESOURCES/GameRuntime.app" "$APP_STAGE/Contents/Resources/GameRuntime.app"
/usr/bin/ditto --norsrc "$DONOR_RESOURCES/Underground 2 FPS.app" "$APP_STAGE/Contents/Resources/Underground 2 FPS.app"
cp -f "$DONOR_RESOURCES/RuntimeBootstrap" "$APP_STAGE/Contents/Resources/RuntimeBootstrap"
cp -f "$DONOR_RESOURCES/x87sidecar" "$APP_STAGE/Contents/Resources/x87sidecar"
ln -sfn "GameRuntime.app/Contents/Resources/wine" "$APP_STAGE/Contents/Resources/wine"
for RECORD in Runtime.json Attributions.txt; do
    if [[ -f "$DONOR_RESOURCES/$RECORD" ]]; then cp "$DONOR_RESOURCES/$RECORD" "$APP_STAGE/Contents/Resources/"; fi
done
if [[ "$(basename "$EXE" | tr '[:upper:]' '[:lower:]')" == "gta_sa.exe" && -f "$SCRIPT_DIR/btp-game-profile.py" ]]; then
    python3 -I -B "$SCRIPT_DIR/btp-game-profile.py" --patch-gta-runtime "$APP_STAGE/Contents/Resources"
    # Match the working GTA recipe: avoid the unavailable Wine WM reader and
    # retain the game's native audio libraries. Only the prepared copy changes.
    OVERRIDES+=";winegstreamer=;wmvcore=;vorbisFile=n,b;vorbisHooked=n,b;eax=n,b;ogg=n,b;vorbis=n,b;xinput1_3=b,n"
    [[ -n "$GAME_ARGS" ]] || GAME_ARGS='-memory 1048576'
fi

# Valores escritos com %q para sobreviver a espaços, aspas e barras invertidas no launch-game.sh.
EXE_WIN="C:\\$(printf '%s' "$GAME_REL/$EXE" | tr '/' '\\')"
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
if [[ "${BTP_PROFILE_X87:-0}" == 1 ]]; then
    export X87_SAMPLE="$DATA/Registros/x87-profile" X87_SAMPLE_HZ=500 X87_SAMPLE_REPORT=5
fi
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
} > "$APP_STAGE/Contents/Resources/launch-game.sh"
chmod 755 "$APP_STAGE/Contents/Resources/launch-game.sh"

plist() { /usr/libexec/PlistBuddy -c "$1" "$APP_STAGE/Contents/Info.plist" >/dev/null; }
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
    cp "$SCRIPT_DIR/BTPGameLauncher" "$APP_STAGE/Contents/MacOS/BTPGame"
else
    LAUNCHER_SRC="$ROOT_DIR/src/BTPGameLauncher.swift"
    [[ -f "$LAUNCHER_SRC" ]] || LAUNCHER_SRC="$SCRIPT_DIR/BTPGameLauncher.swift"
    xcrun swiftc -O -target arm64-apple-macos14.0 "$LAUNCHER_SRC" -o "$APP_STAGE/Contents/MacOS/BTPGame"
fi
chmod 755 "$APP_STAGE/Contents/MacOS/BTPGame"

echo "[5/5] Assinando o aplicativo..."
if [[ -f "$SCRIPT_DIR/btp-clean-metadata.py" ]]; then python3 -I -B "$SCRIPT_DIR/btp-clean-metadata.py" "$APP_STAGE"; fi
plutil -lint "$APP_STAGE/Contents/Info.plist"
bash -n "$APP_STAGE/Contents/Resources/launch-game.sh"
codesign --force --deep --sign - "$APP_STAGE"
codesign --verify --deep --strict "$APP_STAGE"

if [[ -e "$TARGET_APP" || -L "$TARGET_APP" ]]; then
    mkdir -p "$DATA_DIR/Backups/Apps"
    BACKUP_DIR="$(mktemp -d "$DATA_DIR/Backups/Apps/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
    BACKUP_APP="$BACKUP_DIR/$TITLE.app"
    mv "$TARGET_APP" "$BACKUP_APP"
fi
mv "$APP_STAGE" "$TARGET_APP"
if [[ -n "$BACKUP_APP" ]]; then echo "Versão anterior preservada em: $BACKUP_APP"; fi
echo "✅ Aplicativo Mac preparado para teste: $TARGET_APP"
