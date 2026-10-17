#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GAME_DIR="${1:-$HOME/Library/Application Support/Breaking the Pattern/Games/Call of Duty Black Ops II}"
DATA_DIR="$HOME/Library/Application Support/Call of Duty Black Ops II"
TARGET_APP="$HOME/Applications/Call of Duty Black Ops II.app"
DONOR_RESOURCES="$HOME/Applications/Need for Speed Underground 2.app/Contents/Resources"

echo "[1/4] Configurando motor BTP HyperMetal Engine (Direct Metal D3D11) para Black Ops II..."

mkdir -p "$GAME_DIR"
cat << 'EOF' > "$GAME_DIR/mtld3d.conf"
shader.asyncCompile = true
depth.aliasSameSize = false
present.maxFps = 0
present.maxFrameLatency = 1
query.flushImmediate = true
query.eventImmediate = true
EOF

echo "[2/4] Preparando ícone tático do Call of Duty: Black Ops II..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$ROOT_DIR/src/CODBO2GameIcon.icns" ]; then
    cp "$ROOT_DIR/src/CODBO2GameIcon.icns" "/tmp/CODBO2GameIcon.icns"
elif [ -f "$SCRIPT_DIR/../Resources/CODBO2GameIcon.icns" ]; then
    cp "$SCRIPT_DIR/../Resources/CODBO2GameIcon.icns" "/tmp/CODBO2GameIcon.icns"
elif [ -f "$SCRIPT_DIR/CODBO2GameIcon.icns" ]; then
    cp "$SCRIPT_DIR/CODBO2GameIcon.icns" "/tmp/CODBO2GameIcon.icns"
else
    ICONSET_DIR="/tmp/CODBO2Icon.iconset"
    rm -rf "$ICONSET_DIR" && mkdir -p "$ICONSET_DIR"

    cat << 'EOF' > /tmp/make_codbo2_icon.swift
import AppKit

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
NSGraphicsContext.current?.imageInterpolation = .high

let iconRect = NSRect(x: 84, y: 84, width: 856, height: 856)
let path = NSBezierPath(roundedRect: iconRect, xRadius: 192, yRadius: 192)

// Deep tactical carbon background
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0),
    ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.06, alpha: 1.0)
)!
gradient.draw(in: path, angle: -45)

// Outer glowing orange border
NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.10, alpha: 0.5).setStroke()
path.lineWidth = 4
path.stroke()

let centerPoint = NSPoint(x: 512, y: 520)

// Top: COD text
let font = NSFont.systemFont(ofSize: 130, weight: .heavy)
let text = "BLACK OPS" as NSString
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedWhite: 0.92, alpha: 1.0)
]
let textSize = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: centerPoint.x - textSize.width / 2, y: centerPoint.y + 60), withAttributes: attrs)

// Giant Roman "II" in vibrant tactical orange
let numFont = NSFont.systemFont(ofSize: 260, weight: .black)
let numText = "II" as NSString
let numAttrs: [NSAttributedString.Key: Any] = [
    .font: numFont,
    .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.10, alpha: 1.0)
]
let numSize = numText.size(withAttributes: numAttrs)
numText.draw(at: NSPoint(x: centerPoint.x - numSize.width / 2, y: centerPoint.y - 180), withAttributes: numAttrs)

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: "/tmp/codbo2_base.png"))
EOF

    xcrun swift /tmp/make_codbo2_icon.swift
    for s in 16 32 128 256 512; do
        sips -z $s $s "/tmp/codbo2_base.png" --out "$ICONSET_DIR/icon_${s}x${s}.png" >/dev/null
        s2=$((s * 2))
        sips -z $s2 $s2 "/tmp/codbo2_base.png" --out "$ICONSET_DIR/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET_DIR" -o "/tmp/CODBO2GameIcon.icns"
fi

echo "[3/4] Preparando prefixo Wine + BTP HyperMetal Engine via APFS..."
mkdir -p "$DATA_DIR/Registros"
if [ ! -d "$DATA_DIR/prefix-metal" ]; then
    cp -Rc "$DONOR_RESOURCES/PrefixSeed" "$DATA_DIR/prefix-metal"
fi
mkdir -p "$DATA_DIR/prefix-metal/dosdevices"
ln -sfn "/" "$DATA_DIR/prefix-metal/dosdevices/z:"
mkdir -p "$DATA_DIR/prefix-metal/drive_c/Games"
ln -sfn "$GAME_DIR" "$DATA_DIR/prefix-metal/drive_c/Games/BlackOps2"

echo "[4/4] Criando pacote Call of Duty Black Ops II.app..."
rm -rf "$TARGET_APP"
mkdir -p "$TARGET_APP/Contents/MacOS" "$TARGET_APP/Contents/Resources"

cat << 'EOF' > "$TARGET_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Call of Duty: Black Ops II</string>
	<key>CFBundleExecutable</key>
	<string>BlackOps2</string>
	<key>CFBundleIconFile</key>
	<string>GameIcon</string>
	<key>CFBundleIdentifier</key>
	<string>org.lendaii.codbo2</string>
	<key>CFBundleName</key>
	<string>Call of Duty Black Ops II</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0</string>
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

cp "/tmp/CODBO2GameIcon.icns" "$TARGET_APP/Contents/Resources/GameIcon.icns"
cp -Rc "$DONOR_RESOURCES/GameRuntime.app" "$TARGET_APP/Contents/Resources/GameRuntime.app"
cp -Rc "$DONOR_RESOURCES/Underground 2 FPS.app" "$TARGET_APP/Contents/Resources/Underground 2 FPS.app"
cp -f "$DONOR_RESOURCES/RuntimeBootstrap" "$TARGET_APP/Contents/Resources/RuntimeBootstrap"
cp -f "$DONOR_RESOURCES/x87sidecar" "$TARGET_APP/Contents/Resources/x87sidecar"
ln -sfn "GameRuntime.app/Contents/Resources/wine" "$TARGET_APP/Contents/Resources/wine"

cat << 'EOF' > "$TARGET_APP/Contents/Resources/launch-game.sh"
#!/bin/bash
set -eu
RESOURCES="$1"
DATA="$2"
WINE="$RESOURCES/GameRuntime.app/Contents/MacOS/wine"
GAME="$DATA/prefix-metal/drive_c/Games/BlackOps2"
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
export WINEDLLOVERRIDES='winegstreamer=;dinput8=n;xinput1_3=b,n;winemenubuilder.exe='
export WINE_COMPATDB=$'v=5\nname=codbo2;exe=t6sp.exe;dxgi=dxmt'
export WINEDEBUG=-all,+fps,+timestamp
export MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1 MTL_HUD_OPACITY=0
printf 'Abrindo BTP HyperMetal Engine (Call of Duty: Black Ops II). Registro: %s\n' "$LOG"
PIDFILE="$LOG.pid"
"$RESOURCES/RuntimeBootstrap" "$PIDFILE" "$RESOURCES/x87sidecar" --cooperative "$WINE" 'C:\Games\BlackOps2\t6sp.exe' > "$LOG" 2>&1 &
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

cat << 'EOF' > /tmp/CODBO2Launcher.swift
import AppKit
import Foundation

final class CODBO2Launcher: NSObject, NSApplicationDelegate {
    private var child: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let resources = Bundle.main.resourceURL else {
            NSApp.terminate(nil)
            return
        }
        let fm = FileManager.default
        let dataURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Call of Duty Black Ops II")
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
let delegate = CODBO2Launcher()
app.delegate = delegate
app.run()
EOF
xcrun swiftc -O -target arm64-apple-macos14.0 /tmp/CODBO2Launcher.swift -o "$TARGET_APP/Contents/MacOS/BlackOps2"
chmod 755 "$TARGET_APP/Contents/MacOS/BlackOps2"

for ATTR in com.apple.FinderInfo com.apple.ResourceFork; do
    xattr -r -d "$ATTR" "$TARGET_APP" 2>/dev/null || true
done
codesign --force --deep --sign - "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"

mkdir -p "$HOME/Movies/Apps criados"
cp -Rf "$TARGET_APP" "$HOME/Movies/Apps criados/" 2>/dev/null || true

echo "✅ App nativo criado com sucesso: $TARGET_APP"
