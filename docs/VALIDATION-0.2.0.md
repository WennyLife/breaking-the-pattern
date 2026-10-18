# BTP 0.2.0 preview — validation, 18 October 2026

The interface and update workflow are validated separately from game compatibility.

| Check | Observed result |
|---|---|
| Native ARM64 build | Completed; deep/strict local code signature verified |
| Portuguese and English | Both observed in the running UI; language menu switches library, controls, notices, and update settings; Mac-language default restored |
| Runtime independence | Verified official archive hashes; created a fresh Wine prefix and executed a Windows command without a donor game app |
| Destination tools | Bundled Python imports and runtime helper ran with PATH limited to /usr/bin:/bin; signature verified again afterwards |
| Packaging protection | Seven isolated cases passed, including failure/rollback and preservation of the previous app |
| Runtime/profile tests | Seven cases passed: malformed paths/links, checksum failure, incomplete prefix, unknown edition, preservation of settings/backups, renderer hash gate |
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

The new donor-free generator produced separately signed NFS/GTA apps. **No new playable session was confirmed.** Fresh NFS startup exposed a null read at0x006f7429. The recipe now includes a canonical Windows path, Windows7, language/locale, and the exact `CD Drive` registry value, but this is not yet evidence of a fixed playable session. A window-mode comparison and enabling x87 profiling did not establish success. GTA's generated app was also not confirmed playable.

Relevant runtime DLLs, x87sidecar, and RuntimeBootstrap matched the existing working NFS runtime. Further investigation should compare installer registry defaults (including NotFirstTime/SIZE) and observe a real foreground session before replacing any working game app or advertising the new preparation as validated.

A black automated Wine-window capture is an observation limit; it is not by itself proof that rendering failed. Conversely, a process/window or successful package is not proof of gameplay. No new FPS, audio, controller, campaign, or other-Mac validation is claimed here.

Binary installers are prepared locally. Public binary release remains pending; the GitHub source and this report are published without a universal-conversion or performance claim.
