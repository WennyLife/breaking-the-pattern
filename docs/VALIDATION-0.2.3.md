# BTP 0.2.3 build 10 — validation

Date: 2026-10-18. Host: MacBook Pro M5 Pro, 24 GB. Initial scope: accepted executable editions in `scripts/game-profiles.json`.

## Preparation and packaging

- 38 unit tests and seven isolated packaging cases passed. Failure propagation, symlink isolation, configuration rollback, shell-safe settings export, incompatible runtime rejection and explicit recipe precedence covered.
- Native arm64 build and strict ad hoc signature passed. Bundled Python helpers executed with `-I -B` and `/usr/bin:/bin` as the initial PATH. No donor override or developer tools were needed for game preparation.
- Private NFS/GTA sources had their manual ASI/Widescreen/SilentPatch components removed; GTA's original audio DLL was restored before the test. Required official components were provisioned automatically, with hashes checked.
- Both apps were prepared successfully, then regenerated with the final catalog-driven launcher settings. Existing INIs were preserved. Fresh NFS INI uses WindowedMode=4 and FPSLimit=0. GTA renderer cap remains 60.
- Shared runtime DLL SHA256 remained `d9c04787c9e7d1bddd25b340d363074f4d3071e5bac3735267bacde5ed7412a7`; GTA patch is restricted to the generated app copy.

## Gameplay

- NFSU2 Release Validation: user confirmed driving with normal sound and commands on the new generated copy.
- GTA Release Validation: final gameplay confirmation pending. The user retracted an accidental black-screen/error survey answer; do not treat it as a confirmed failure. Tests were explicitly paused on 2026-10-18 at 12:12 before receiving the corrected gameplay answer.
- Earlier independent GTA recipe validation already reached gameplay, sound and CJ movement. The new plugin-free source preparation is validated separately above.

## Distribution and practical limits

The public release workflow runs tests, builds the app, verifies extracted ZIP/app signatures and DMG, then publishes installers and checksums. The Sparkle feed is signed locally for the exact public ZIP only after its download exists. Publication and feed completion must be checked separately; a build alone does not prove delivery.

No game data, executables, saves or personal prefixes are distributed. Original installed games and saves are outside the test prefixes. No new sustained FPS benchmark, physical controller mapping, full campaign or second physical Mac is claimed. BTP is ad hoc signed, not Apple-notarized; first launch on another Mac may require local user approval. Rosetta and internet are required for the first preparation. Unknown editions are not promised compatible. Splinter Cell remains outside this initial release.

## Paused checkpoint — 2026-10-18 12:13

No public installers, tag or new appcast item have been published. The release pipeline has been implemented and reviewed but has not run on GitHub Actions yet. Installed/archived current BTP remains 0.2.2 build9. Candidate 0.2.3 build10 is saved separately. Original game files checked: 1,585, no differences. Test games/launchers and the updater check window were closed; no test-specific sleep assertion remains. Claude still owns system/display wake locks and was preserved. Resume only when the user asks.
