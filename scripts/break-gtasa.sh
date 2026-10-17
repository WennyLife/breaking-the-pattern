#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES_DIR="$ROOT_DIR/patches/gtasa"
GAME_DIR="${1:-$HOME/Library/Application Support/Breaking the Pattern/Games/GTA San Andreas}"
DATA_DIR="$HOME/Library/Application Support/Grand Theft Auto San Andreas"
TARGET_APP="$HOME/Applications/Grand Theft Auto San Andreas.app"
DONOR_RESOURCES="$HOME/Applications/Need for Speed Underground 2.app/Contents/Resources"

echo "[1/4] Aplicando patch v1.0 US No-DVD, Ultimate ASI Loader, WidescreenFix, SilentPatch e Tradução PT-BR..."
if [ -f "$GAME_DIR/vorbisFile.dll" ] && [ ! -f "$GAME_DIR/vorbisHooked.dll" ]; then
    cp -f "$GAME_DIR/vorbisFile.dll" "$GAME_DIR/vorbisHooked.dll"
fi
cp -f "$PATCHES_DIR/gta_sa.exe" "$GAME_DIR/gta_sa.exe"
cp -f "$PATCHES_DIR/vorbisFile.dll" "$GAME_DIR/vorbisFile.dll"
mkdir -p "$GAME_DIR/scripts" "$GAME_DIR/text" "$GAME_DIR/models/txd"
cp -Rf "$PATCHES_DIR/scripts/"* "$GAME_DIR/scripts/"
if [ -f "$PATCHES_DIR/text/american.gxt" ]; then
    cp -f "$PATCHES_DIR/text/american.gxt" "$GAME_DIR/text/american.gxt"
fi
if [ -d "$PATCHES_DIR/models" ]; then
    cp -f "$PATCHES_DIR/models/"*.txd "$GAME_DIR/models/" 2>/dev/null || true
fi
if [ -d "$PATCHES_DIR/models/txd" ]; then
    cp -Rf "$PATCHES_DIR/models/txd/"* "$GAME_DIR/models/txd/" 2>/dev/null || true
fi
if [ -f "$GAME_DIR/movies/Logo.mpg" ]; then
    mv -f "$GAME_DIR/movies/Logo.mpg" "$GAME_DIR/movies/Logo.mpg.bak"
fi
if [ -f "$GAME_DIR/movies/GTAtitles.mpg" ]; then
    mv -f "$GAME_DIR/movies/GTAtitles.mpg" "$GAME_DIR/movies/GTAtitles.mpg.bak"
fi
cat << 'EOF' > "$GAME_DIR/mtld3d.conf"
shader.asyncCompile = false
depth.aliasSameSize = false
present.maxFps = 60
present.maxFrameLatency = 1
query.flushImmediate = true
query.eventImmediate = true
EOF

echo "[2/4] Extraindo ícone original do GTA San Andreas (data/Icons/app.ico)..."
ICON_SRC="$GAME_DIR/data/Icons/app.ico"
ICONSET_DIR="/tmp/GTASAIcon.iconset"
rm -rf "$ICONSET_DIR" && mkdir -p "$ICONSET_DIR"
if [ -f "$ICON_SRC" ]; then
    sips -s format png "$ICON_SRC" --out "/tmp/gtasa_raw_ico.png" >/dev/null
    cat << 'EOF' > /tmp/make_gtasa_icon.swift
import AppKit

let srcImg = NSImage(contentsOfFile: "/tmp/gtasa_raw_ico.png")!
let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .none
let iconRect = NSRect(x: 84, y: 84, width: 856, height: 856)
let path = NSBezierPath(roundedRect: iconRect, xRadius: 192, yRadius: 192)
NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1.0).setFill()
path.fill()
path.addClip()
let innerRect = NSRect(x: 140, y: 140, width: 744, height: 744)
srcImg.draw(in: innerRect, from: .zero, operation: .sourceOver, fraction: 1.0)
NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
path.lineWidth = 6
path.stroke()
NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "/tmp/gtasa_base.png"))
EOF
    xcrun swift /tmp/make_gtasa_icon.swift
else
    cp "$ROOT_DIR/src/AppIcon.png" "/tmp/gtasa_base.png"
fi
for s in 16 32 128 256 512; do
    sips -z $s $s "/tmp/gtasa_base.png" --out "$ICONSET_DIR/icon_${s}x${s}.png" >/dev/null
    s2=$((s * 2))
    sips -z $s2 $s2 "/tmp/gtasa_base.png" --out "$ICONSET_DIR/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "/tmp/GTASAGameIcon.icns"

echo "[3/4] Preparando ambiente Wine + Direct Metal (mtld3d) via clonagem APFS..."
mkdir -p "$DATA_DIR/Registros"
if [ ! -d "$DATA_DIR/prefix-metal" ]; then
    cp -Rc "$DONOR_RESOURCES/PrefixSeed" "$DATA_DIR/prefix-metal"
fi
mkdir -p "$DATA_DIR/prefix-metal/dosdevices"
ln -sfn "/" "$DATA_DIR/prefix-metal/dosdevices/z:"
mkdir -p "$DATA_DIR/prefix-metal/drive_c/Games"
ln -sfn "$GAME_DIR" "$DATA_DIR/prefix-metal/drive_c/Games/GTASA"
mkdir -p "$DATA_DIR/prefix-metal/drive_c/users/crossover/Documents/GTA San Andreas User Files/Gallery"
mkdir -p "$DATA_DIR/prefix-metal/drive_c/users/crossover/Documents/GTA San Andreas User Files/User Tracks"

echo "[4/4] Codificando aplicativo nativo Grand Theft Auto San Andreas.app..."
rm -rf "$TARGET_APP"
mkdir -p "$TARGET_APP/Contents/MacOS" "$TARGET_APP/Contents/Resources"

cat << 'EOF' > "$TARGET_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Grand Theft Auto San Andreas</string>
	<key>CFBundleExecutable</key>
	<string>GTASA</string>
	<key>CFBundleIconFile</key>
	<string>GameIcon</string>
	<key>CFBundleIdentifier</key>
	<string>org.lendaii.gtasa</string>
	<key>CFBundleName</key>
	<string>Grand Theft Auto San Andreas</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

cp "/tmp/GTASAGameIcon.icns" "$TARGET_APP/Contents/Resources/GameIcon.icns"
cp -Rc "$DONOR_RESOURCES/GameRuntime.app" "$TARGET_APP/Contents/Resources/GameRuntime.app"
cp -Rc "$DONOR_RESOURCES/Underground 2 FPS.app" "$TARGET_APP/Contents/Resources/Underground 2 FPS.app"
cp -f "$DONOR_RESOURCES/RuntimeBootstrap" "$TARGET_APP/Contents/Resources/RuntimeBootstrap"
cp -f "$DONOR_RESOURCES/x87sidecar" "$TARGET_APP/Contents/Resources/x87sidecar"
ln -sfn "GameRuntime.app/Contents/Resources/wine" "$TARGET_APP/Contents/Resources/wine"

python3 - "$TARGET_APP/Contents/Resources/GameRuntime.app/Contents/Resources/wine/lib/wine/d3d9/mtld3d/i386-windows/d3d9.dll" "$GAME_DIR/gta_sa.exe" << 'PYEOF'
import sys
p = sys.argv[1]
data = open(p, "rb").read()
patched = data.replace(b"\xb8\xff\xff\x9e\x00", b"\xb8\xff\xff\x9e\x01")
if patched != data:
    open(p, "wb").write(patched)

exe_path = sys.argv[2]
exe_data = open(exe_path, "rb").read()
orig_exe = exe_data
old_msaa = bytes.fromhex("8b0d30248e00893d50c0c9003bcb893d54c0c9007708391d38248e00765d")
new_msaa = bytes.fromhex("8b0d30248e00893d50c0c9003bcb893d54c0c900eb65391d38248e00eb5d")
exe_data = exe_data.replace(old_msaa, new_msaa, 1)
exe_data = exe_data.replace(bytes.fromhex("c70574c0c90000000080"), bytes.fromhex("c70574c0c90001000000"))
exe_data = exe_data.replace(bytes.fromhex("c70558c0c90002000000"), bytes.fromhex("c70558c0c90001000000"))
exe_data = exe_data.replace(bytes.fromhex("c70558c0c90003000000"), bytes.fromhex("c70558c0c90001000000"))
exe_data = exe_data.replace(bytes.fromhex("8b1530248e008b44244c3bd00f84a8020000"), bytes.fromhex("8b1530248e008b44244c3bd0e9a902000090"), 1)
exe_data = exe_data.replace(bytes.fromhex("33c0885e4c885e21"), bytes.fromhex("33c088464c885e21"), 1)
exe_data = exe_data.replace(bytes.fromhex("a09467ba0084c0750da018b3ba0084c075046a00eb026a01"), bytes.fromhex("a09467ba0084c0750da018b3ba0084c075046a01eb026a01"), 1)
exe_data = exe_data.replace(bytes.fromhex("3bc80f85de000000c70574c0c90001000000"), bytes.fromhex("3bc8e9df00000090c70574c0c90001000000"), 1)
exe_data = exe_data.replace(bytes.fromhex("c705805a8a0000002003"), bytes.fromhex("c705805a8a0000000040"), 1)
# Disable SpeedFX (Speed Blur when running or driving)
exe_data = exe_data.replace(bytes.fromhex("83ec3c0fb60581f0b60069c038020000"), bytes.fromhex("c390900fb60581f0b60069c038020000"), 1)
# Disable MotionBlur (Trails ghosting smear)
exe_data = exe_data.replace(bytes.fromhex("8a44240883ec0884c00f84ac000000a1"), bytes.fromhex("c390909083ec0884c00f84ac000000a1"), 1)
if exe_data != orig_exe:
    open(exe_path, "wb").write(exe_data)
PYEOF

cat << 'EOF' > "$TARGET_APP/Contents/Resources/launch-game.sh"
#!/bin/bash
set -eu
RESOURCES="$1"
DATA="$2"
WINE="$RESOURCES/GameRuntime.app/Contents/MacOS/wine"
GAME="$DATA/prefix-metal/drive_c/Games/GTASA"
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
cd "$GAME"
export PATH="$RESOURCES/wine/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export WINEPREFIX="$DATA/prefix-metal"
export WINESERVER="$RESOURCES/wine/bin/wineserver"
export WINEARCH=wow64 WINELOADERNOEXEC=1
export X87_SAMPLE="$DATA/Registros/x87-profile" X87_SAMPLE_HZ=500 X87_SAMPLE_REPORT=5
export ROSETTA_X87_PATH="$RESOURCES/x87sidecar"
export WINEDLLOVERRIDES='winegstreamer=;wmvcore=;vorbisfile=n,b;eax=n,b;ogg=n,b;vorbis=n,b;dinput8=n,b;xinput1_3=b,n;winemenubuilder.exe='
export WINE_COMPATDB=$'v=5\nname=gtasa-metal;exe=gta_sa.exe;d3d9=mtld3d'
export WINEDEBUG=-all,+fps,+timestamp
export MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 MTL_HUD_OPACITY=0
printf 'Abrindo Metal + x87 (GTA SA). Registro: %s\n' "$LOG"
PIDFILE="$LOG.pid"
"$RESOURCES/RuntimeBootstrap" "$PIDFILE" "$RESOURCES/x87sidecar" --cooperative "$WINE" 'C:\Games\GTASA\gta_sa.exe' -memory 1048576 > "$LOG" 2>&1 &
BOOT_PID=$!
for i in {1..100}; do [[ -s "$PIDFILE" ]] && break; sleep 0.05; done
GAME_PID=$(cat "$PIDFILE" 2>/dev/null || echo "")
if [[ -n "$GAME_PID" ]]; then
    printf '%s\n' "$GAME_PID" > "$DATA/Registros/game.pid"
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
chmod 755 "$TARGET_APP/Contents/Resources/launch-game.sh"

cat << 'EOF' > /tmp/GTASALauncher.swift
import AppKit
import Foundation

final class GTASALauncher: NSObject, NSApplicationDelegate {
    private var child: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let resources = Bundle.main.resourceURL else {
            NSApp.terminate(nil)
            return
        }
        let fm = FileManager.default
        let dataURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grand Theft Auto San Andreas")
        try? fm.createDirectory(at: dataURL.appendingPathComponent("Registros"), withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [
            resources.appendingPathComponent("launch-game.sh").path,
            resources.path,
            dataURL.path
        ]
        proc.terminationHandler = { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        do {
            try proc.run()
            child = proc
        } catch {
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = GTASALauncher()
app.delegate = delegate
app.run()
EOF
xcrun swiftc -O -target arm64-apple-macos14.0 /tmp/GTASALauncher.swift -o "$TARGET_APP/Contents/MacOS/GTASA"
chmod 755 "$TARGET_APP/Contents/MacOS/GTASA"

for ATTR in com.apple.FinderInfo com.apple.ResourceFork; do
    xattr -r -d "$ATTR" "$TARGET_APP" 2>/dev/null || true
done
codesign --force --deep --sign - "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
echo "✅ App nativo criado com sucesso: $TARGET_APP"
