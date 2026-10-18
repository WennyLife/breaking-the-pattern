# Development and compatibility components

[Português / apresentação do BTP](../README.md) · [English](../README.en.md)

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

Runtime versions, download URLs, checksums, and source links are in [`scripts/runtime-manifest.json`](../scripts/runtime-manifest.json). The initial runtime excludes Apple's D3DMetal/GPTK components. See [third-party notices](../THIRD_PARTY.md) and [release instructions](../docs/RELEASING.md).

Report the game edition, runtime version, exact symptom, graphics settings, and reproducible steps. A new confirmed fix can become a versioned recipe; unverified attempts do not become automatic rules.

[Support via PayPal](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL) · [MIT license for BTP code](../LICENSE)
