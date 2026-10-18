# Third-party components

BTP's MIT license covers its own code. Dependencies retain their respective licenses and copyrights.

| Component | Version / source | Distribution |
|---|---|---|
| Sparkle | [2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), Sparkle license (MIT plus included notices) | Framework and full upstream LICENSE embedded in BTP Resources/Licenses |
| Python | [CPython 3.13.16 standalone build 20261013](https://github.com/astral-sh/python-build-standalone/releases/tag/20261013), PSF and dependency licenses | Embedded runtime; license texts and build metadata from the matching full archive retained in licenses/Python; unused Windows pip launchers removed |
| Wine | [cx-26.3.0-9 build](https://github.com/athei/wine-build/releases/tag/cx-26.3.0-9), LGPL-2.1-or-later and component notices | Downloaded directly from upstream at first preparation; pinned hash in runtime-manifest.json; Wine source revision linked there |
| x87sidecar | [v1.9.0](https://github.com/athei/x87sidecar/tree/v1.9.0), MIT | Downloaded directly from upstream; source and checksum recorded |
| mtld3d | [athei/mtld3d](https://github.com/athei/mtld3d), upstream license | Included in the pinned upstream Wine build; BTP's GTA recipe changes only the copied renderer, with a hash gate |
| Rosetta | Apple system component | Not bundled or downloaded by BTP; install through macOS and Apple's terms |
| unshield | [twogood/unshield](https://github.com/twogood/unshield), MIT | Optional native extractor with only macOS system-library dependencies; upstream LICENSE embedded in licenses/unshield.txt |

The initial D3D9 runtime excludes the Apple D3DMetal/GPTK directories from the upstream Wine archive. No Apple graphics redistribution license is implied.

The generated runtime includes Runtime.json with component versions, URLs, SHA-256 hashes, source links, and required-file hashes, plus Attributions.txt. Upstream Wine includes additional libraries and notices that are retained in its downloaded tree. This table is not a blanket license for game assets or third-party game mods.

Game files, game mods supplied in user folders, and saves are outside the BTP distribution. No commercial game executable is checked into or bundled with BTP.
