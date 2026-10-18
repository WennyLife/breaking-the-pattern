# BTP 0.2.0 preview — validation, 18 October 2026

The interface and update workflow are validated separately from game compatibility.

| Check | Observed result |
|---|---|
| Native ARM64 build | Completed; deep/strict local code signature verified |
| Portuguese and English | Both observed in the running UI; language menu switches library, controls, notices, and update settings; Mac-language default restored |
| Runtime independence | Verified official archive hashes; created a fresh Wine prefix and executed a Windows command without a donor game app |
| Destination tools | Bundled Python imports and runtime helper ran with PATH limited to /usr/bin:/bin; signature verified again afterwards |
| Packaging protection | Seven isolated cases passed, including failure/rollback and preservation of the previous app |
| Runtime/profile tests | Nine cases passed: malformed paths/links, checksum failure, incomplete prefix, unknown edition, preservation of settings/backups, renderer hash gate, private NFS drive mapping and preservation of an existing mapping |
| Splinter helper regression | Four isolated helper cases passed; gameplay/audio diagnosis remains paused |
| Update archive | Ed25519 signature verified; an intentionally modified archive was rejected |
| Complete update | Isolated build3/version0.1.99 downloaded, verified, installed, and relaunched as build4/version0.2.0; previous app backup verified |
| Installer | Current ZIP integrity and extracted app signature checked; DMG checksum verified, mounted read-only, and contained app signature checked |
| Production feed | Public HTTPS XML endpoint available; empty until public signed assets are uploaded |

The first update test under synchronized Documents could not rename the app. The equivalent local Application Support test succeeded. Install BTP in a local Applications folder.

A post-build smoke test exposed Python bytecode caches being added inside the signed app. All production Python helper calls now use `-I -B`; imports/helper execution followed by signature verification passed. A failed signature check prevented the earlier package from replacing the installed app.

The updater waits for an ongoing game-preparation operation to finish before restarting BTP. It updates BTP.app only. Generated game apps, prefixes, and saves are separate.

## Game boundary

The original working NFS and GTA apps, game folders, quality settings, and saves were preserved. Splinter was not retested.

The new donor-free generator produced separately signed NFS/GTA apps. Fresh NFS startup initially exposed a null read at0x006f7429. Canonical Windows path, Windows7, language/locale and the exact `CD Drive` registry value alone did not resolve it. The user confirmed the earlier black/error result.

Relevant runtime DLLs, x87sidecar, and RuntimeBootstrap matched the existing working NFS runtime. Copying non-secret installer/display defaults (including NotFirstTime/SIZE) did not fix startup. Removing the generic mtld3d.conf alone did not fix it either. Those attempts are not automatic rules.

The original prefix had a D: mapping missing from the fresh C:/Z: prefix. Adding a private D: alias to the copied game folder with the observed Wine drive-type setting passed the earlier startup fault. One attempt subsequently faulted at0x0073927d. After returning to BTP's minimal registry recipe, the next session reached the menu, profile creation and a rendered scene. The user confirmed about a minute of driving with normal sound and commands. The game EXE was not patched; 1,723 copied game files matched the originals byte-for-byte, excluding generated renderer caches/logs. Existing plugins from that game folder remain part of this test.

NFS recipe2 incorporates the private D: mapping, preserves existing mappings, and does not add a generic renderer configuration. The original working app, game, saves and graphics were not changed. Build5's bundled generator was run with PATH limited to /usr/bin:/bin, no donor override, and the isolated D: mapping absent. It recreated that mapping automatically, preserved the new saved profile, produced a signed app, and did not add the generic renderer configuration. The regenerated app reopened; the user confirmed loading that saved profile and normal sound/commands. GTA's initial clean preparation aborted in the unimplemented Wine `winegstreamer_create_wm_sync_reader`. Comparing with the working launcher identified its disabled winegstreamer/wmvcore, native audio overrides and `-memory 1048576`. GTA recipe2 carries those settings forward. The regenerated isolated app reached gameplay; the user confirmed moving CJ with sound and commands. The 60 FPS cap is retained for stability: the user reported that it stopped light/reflection flickering in the original. Existing shader compilation settings are preserved rather than forcing synchronous compilation.

Startup can still require an initial click/key to show or start the first screen. Attempts to transfer macOS activation did not resolve the user's report and were not retained in the launcher. The user explicitly chose to proceed with this as a non-blocking limitation.

A black automated Wine-window capture is an observation limit; it is not by itself proof that rendering failed. Conversely, a process/window or successful package is not proof of gameplay. No sustained FPS benchmark, physical controller, complete campaign, or other-Mac validation is claimed for the new recipe.

Binary installers are prepared locally. Public binary release remains pending; the GitHub source and this report are published without a universal-conversion or performance claim.
