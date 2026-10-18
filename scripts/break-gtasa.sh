#!/bin/bash
# Mesma preparação segura dos demais perfis; não substitui executáveis do jogo.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[[ $# == 1 ]] || { echo "Uso: break-gtasa.sh /pasta/do/GTA" >&2; exit 2; }
exec /bin/bash "$SCRIPT_DIR/break-game.sh" --title "Grand Theft Auto San Andreas" \
    --game-dir "$1" --exe gta_sa.exe --renderer d3d9=mtld3d --winver win7 \
    --overrides 'dinput8=n,b;vorbisFile=n,b;vorbisHooked=n,b;winemenubuilder.exe='
