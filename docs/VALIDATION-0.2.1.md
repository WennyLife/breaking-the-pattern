# BTP 0.2.1 build8 — reusable knowledge catalog

Date: 2026-10-18. This change moves existing preparation decisions into a bundled catalog and records their application. It does not change the NFSU2/GTA recipes or add a supported game.

- 18 unit tests passed, plus 7 packaging/rollback scenarios (25 checks total).
- The generic decision regression covers 480 architecture/year/import combinations, including mixed D3D imports and an unknown COFF date.
- The real local NFSU2/GTA executables were scanned read-only. Renderer, Windows suggestion and x87 decisions matched build7. Their executable hashes remain those in `scripts/game-profiles.json`.
- Both private validation apps were regenerated with the embedded helpers and a system-only PATH, without a donor override. Their decision records show Metal, Win7, x87 and the correct per-game profile; signing passed and previous apps were backed up. No game was launched by this check; original apps/game folders/saves were not changed.
- Arbitrary commands/unknown rule predicates and actions are rejected. A generic rule cannot apply GTA's frame cap/renderer patch or NFS's private drive mapping. Per-game and explicit settings remain separate from the recorded generic suggestions.
- Build, signing and package verification are recorded with the delivered installers in the local central archive.

No new gameplay session, FPS benchmark, physical controller test or other-Mac installation was performed for this refactor. Previous user-confirmed isolated gameplay is described in [0.2.0 validation](VALIDATION-0.2.0.md). Automatic acquisition of all game-folder plugins and an autonomous Auto-Healer remain pending. Public binary upload/notarization are separate pending steps; the public feed must remain empty until signed assets exist.
