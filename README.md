<div align="center">

# ⚡ Breaking the Pattern

![Breaking the Pattern icon](assets/icon.png)

**Prepare your own Windows games for Apple Silicon Macs.**

[Releases](https://github.com/WennyLife/breaking-the-pattern/releases) · [Português](README.pt-BR.md) · [How it works](docs/METODO-E-VALIDACAO.md)

**0.2.0 Preview · English / Português · macOS 15+ · Apple Silicon**

</div>

BTP prepares a separate Mac launcher and a Wine compatibility environment for a game folder you provide. It downloads its own pinned runtime components, verifies their SHA-256 checksums, and applies an edition-specific recipe. You do not need a previously prepared NFS app or Xcode on the destination Mac.

**Games, game executables, saves, cracks, and personal Wine prefixes are not included.** Supply your own game files. BTP does not download commercial games or replace their executables.

## Getting started

The 0.2.0 ZIP/DMG preview is built and verified locally. Its public binary upload is pending; this repository currently provides the source and build instructions. The update feed remains empty until signed assets are published.

1. Download the current DMG or ZIP from [Releases](https://github.com/WennyLife/breaking-the-pattern/releases). Copy BTP to your Applications folder.
2. Open BTP and select your game folder. Install Rosetta through macOS if it is missing. Internet access is needed for the first runtime download (about 235 MB; roughly 1.3 GB expanded).
3. Click **BREAK**. The initial recipes target the tested editions of **Need for Speed Underground 2** and **GTA San Andreas**.
4. Launch the generated game app and verify gameplay, sound, input, and saving. **Prepared** means packaging completed; it does not mean every mission was verified.

Use **BTP → Language / Idioma** to choose English, Português (Brasil), or the Mac language. The language setting changes BTP, not the language files of a game.

This preview is locally ad hoc signed, not Apple-notarized. First launch on another Mac and a complete clean-machine game installation still need independent validation.

## Initial game scope

| Game | Recipe | Current limit |
|---|---|---|
| Need for Speed Underground 2 | Direct3D 9 → Metal, x87sidecar, Windows 7, consistent `C:\Games\NFSU2` path/registry and private D: data mapping | Tested executable edition only; existing game-folder plugins/settings are preserved |
| GTA San Andreas | Direct3D 9 → Metal, copied renderer adjustment, Windows 7, 60 FPS cap | Tested user-supplied executable edition only; no executable replacement |
| Splinter Cell Conviction | Existing local prepared apps can still be opened | Experimental; character voices remain unresolved. Not part of this initial preparation release |

The accepted executable hashes and recipe versions are in [`scripts/game-profiles.json`](scripts/game-profiles.json). Unknown editions are rejected before preparing a runtime. An edition match is a compatibility gate, not an authenticity or malware check. Existing game-folder fixes are retained; this release does not yet acquire every third-party game mod automatically.

The original local NFS/GTA sessions were playable. The new donor-free runtime booted a fresh Windows prefix and ran a command successfully. An isolated NFS copy then reached a rendered scene and the user confirmed driving, sound, and commands after the missing private D: mapping was added; this uses the known local game folder, including its existing plugins. The regenerated GTA launcher also reached gameplay; the user confirmed moving CJ with normal sound and commands. Those results do not guarantee a sustained frame rate, every mission, or every Mac. GTA stays capped at 60 FPS because higher rates caused problems and light/reflection flickering in user testing. No 4K/60 or universal-conversion claim is made. See the [validation record](docs/VALIDATION-0.2.0.md) for the exact scope and remaining checks.

## Updates inside BTP

Open **BTP → Updates…** or use the circular arrow in the header. Automatic checks can be disabled. You choose when to install and relaunch.

Updates use [Sparkle](https://sparkle-project.org/), an HTTPS feed, and Ed25519-signed archives. Before an offered update proceeds, BTP saves and verifies a copy of its previous app bundle in `~/Library/Application Support/Breaking the Pattern/Backups/Updates/`. Updating BTP does not replace generated game apps, prefixes, or saves. New game preparation uses the new recipes; existing game apps stay on their previous components until deliberately prepared again.

Install BTP in a local Applications folder. A test from a synchronized Documents folder failed to replace the app; the same signed update installed and relaunched successfully from a local Application Support test location.

## What actually runs

The BTP interface and launchers are native Swift/ARM64 applications. The game remains its Windows executable. [Wine](https://github.com/athei/wine-build) provides Windows APIs, Rosetta runs Intel code, [x87sidecar](https://github.com/athei/x87sidecar) assists compatible x87 workloads, and [mtld3d](https://github.com/athei/mtld3d) translates Direct3D 9 to Metal.

BTP does not decompile a game into a new native Mac source project. “HyperMetal” and “Neural” are project labels for these components; they do not imply use of Apple's Neural Engine. APFS cloning can share disk blocks initially; game data, caches, and backups still consume storage.

The separate FPS overlay toggles with **Command + Option + 9**. Its Wine/Metal adapters report interval averages, not universal game coverage or per-frame minimums.

## Build and contribute

On an Apple Silicon development Mac with Apple's command-line tools and Python 3:

```sh
bash scripts/build.sh --build-only
python3 tests/test_runtime.py
python3 tests/test_packaging.py
python3 tests/test_splinter_profile.py
```

The build downloads pinned Python and Sparkle dependencies and compiles the launchers/helpers. It does not need a game donor. `--install` publishes a verified build to the local Applications folder and the central app archive, preserving previous versions.

Runtime versions, download URLs, checksums, and source links are in [`scripts/runtime-manifest.json`](scripts/runtime-manifest.json). The initial runtime excludes Apple's D3DMetal/GPTK components. See [third-party notices](THIRD_PARTY.md) and [release instructions](docs/RELEASING.md).

Report the game edition, runtime version, exact symptom, graphics settings, and reproducible steps. A new confirmed fix can become a versioned recipe; unverified attempts do not become automatic rules.

[Support via PayPal](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL) · [MIT license for BTP code](LICENSE)
