# Compatibility knowledge / Base de compatibilidade

The product goal is **game folder → BREAK → independent game app**, with BTP managing the required compatibility components. Users should not need to write code or install plugins manually. This is an engineering goal, not a universal compatibility claim.

## Implemented

- `scripts/compatibility-rules.json`: bundled, versioned reusable decisions for graphics API, i386/x87 and the existing legacy Windows heuristic. These rules select preparation settings; they do not certify gameplay.
- `scripts/btp-rules.py`: a restricted evaluator. Rule data cannot run shell commands, patch binaries or download arbitrary files. First matching action wins for each setting.
- `scripts/btp-peinfo.py`: extracts executable facts and applies the rule catalog.
- `scripts/game-profiles.json` and `scripts/btp-game-profile.py`: edition-specific NFSU2/GTA recipes, with executable hash gates. These take precedence over generic suggestions. NFS's private D: mapping and GTA's renderer adjustment/60 FPS cap must not be applied to unrelated games.
- `Registros/CompatibilityPlan.json` in each newly prepared game's data folder: records the executable hash, catalog hash/revision, matched rules and effective settings, including explicit/profile overrides. This is a preparation record, not proof of gameplay.

The catalog ships inside the signed BTP app and travels through the existing app update mechanism. No server or AI subscription is required to evaluate it. Existing game apps and original folders are not modified by updating BTP. The unchanged generic decisions were compared against the previous implementation; the reusable mechanism does not add a newly supported game.

## How knowledge becomes support

The intended model is compositional: a new title may need one reusable operation learned from NFSU2 and another learned from GTA, rather than inheriting either full preset. For example, Most Wanted could reuse a matching graphics/runtime decision and a separately verified library correction. This is a hypothetical product example, not evidence that Most Wanted is supported. Each operation needs applicability conditions, runtime/version compatibility, conflict handling and its own validation. The current evaluator composes only the existing graphics/Windows/x87 decisions; symptom-driven combination of arbitrary fixes is a later step.

1. Identify an actual failure and the exact edition/runtime/settings.
2. Reproduce a fix in a private copy; preserve failed attempts as evidence.
3. Decide whether the cause is shared or game-specific. Similar age, DirectX version or engine name alone is insufficient to transfer a binary patch or frame cap.
4. Encode a reusable rule with clear conditions, or a versioned game recipe with an executable gate. New action types require evaluator implementation and review; JSON alone cannot teach arbitrary operations.
5. Test the resulting preparation and gameplay, sound, input, saves/reopening and relevant performance separately.
6. Publish a verified BTP update with the new supported scope.

## Still pending

Automatic acquisition/configuration of all game-specific mods is not complete: the NFS/GTA sessions used known game folders with plugins already present. The runtime provider is independent, but this does not yet establish that a plugin-free retail folder reproduces the same result. Unattended log-based diagnosis, trial/fallback and an Auto-Healer are not implemented. New editions/other Macs still need validation. No native game recompilation or DRM bypass is performed.

## Português

A inteligência do BTP é uma **base de soluções comprovadas**, com duas camadas: regras que podem ser reutilizadas e receitas exclusivas de uma edição do jogo. Uma descoberta só vira suporte anunciado depois de o aplicativo gerado funcionar numa partida. Não basta usar o mesmo DirectX para receber todas as correções de outro jogo.

O catálogo agora é lido pelo fluxo real de preparação e registra por que cada decisão foi tomada. Ele preserva as decisões anteriores; não acrescenta aprendizado autônomo nem promete compatibilidade com qualquer pasta. A meta continua ser dispensar código/plugins manuais para a pessoa que usa o BTP; componentes de terceiros podem continuar existindo internamente e precisam ser gerenciados e verificados pela ferramenta.
