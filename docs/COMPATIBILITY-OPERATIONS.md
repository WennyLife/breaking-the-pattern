# Modelo de Operações de Compatibilidade — BTP

Data: 2026-10-18.
Este documento descreve a arquitetura de **Operações Componíveis** do Breaking the Pattern, permitindo que soluções aprendidas em jogos individuais sejam combinadas de forma modular, segura e reproduzível para novos títulos.

---

## 1. Princípio de Projeto: Composição vs Herança Monolítica

Anteriormente, cada jogo dependia de um "preset" rígido ou script monolítico. Quando um novo jogo apresentava um problema parecido (por exemplo, um jogo D3D9 de 32 bits que precisa de x87 e widescreen), a tentação seria copiar o preset inteiro de um jogo anterior.

**Problema da cópia de preset:**
- O *Need for Speed Underground 2* precisa de um alias para a unidade `D:` no prefixo para não falhar na rotina `RealCore`. Copiar essa regra para outro jogo pode sobrescrever mapeamentos legítimos de mídia.
- O *GTA San Andreas* requer limite estrito de 60 FPS no renderizador porque a física da RenderWare acelera e quebra acima disso. Aplicar esse limite indiscriminadamente em jogos cujo motor suporte 120 FPS ou mais causaria degradação desnecessária.
- O *Splinter Cell Conviction* requer `SkipSystemDetection=1` via FusionFix para não fechar na tela de hardware.

**A solução do BTP: Operações Atômicas e Componíveis**
Em vez de clonar presets, o BTP decompõe as correções em **Operações**, cada uma com:
- **Identidade única (`id`)** e categoria (`graphics`, `cpu`, `os`, `storage`, `engine`, `media`, `plugin`).
- **Condição de aplicação (`when`)**: predicados precisos sobre arquitetura PE, DLLs importadas, ano de compilação ou receita comprovada.
- **Conflitos declarados (`conflicts_with`)**: se duas operações forem mutuamente exclusivas, a de maior precedência vence e o conflito é registrado.
- **Ambiente compatível (`runtime_compat`)**: versões de Wine ou bibliotecas requeridas.
- **Reversibilidade (`reversible`)**: qualquer modificação no disco do jogo gera backup com data/hora em `Backups/Operations/`.
- **Evidência (`evidence`)**: referência direta ao teste empírico onde a solução foi validada.

---

## 2. Catálogo de Operações Implementadas

| ID da Operação | Categoria | Condição (`when`) | Ação Principal | Conflita com | Evidência / Origem |
|---|---|---|---|---|---|
| `op.graphics.d3d9.mtld3d` | graphics | `d3d9.dll` | Renderer: `d3d9=mtld3d` | `dxmt`, `gptk` | NFSU2, GTA SA |
| `op.graphics.d3d11.dxmt` | graphics | `d3d11.dll`, `dxgi.dll` | Renderer: `dxgi=dxmt` | `mtld3d`, `gptk` | Splinter Cell, D3D11 |
| `op.cpu.x87sidecar` | cpu | `arch == i386` | Rosetta sidecar ativo | — | NFSU2, GTA SA (física 32-bit) |
| `op.os.win7_legacy` | os | `year < 2012` | Windows version: `win7` | — | Splinter Cell, NFSU2 |
| `op.storage.nfs_data_drive` | storage | Receita `nfsu2` | Cria link privado `dosdevices/d:` | — | Erro 0x006f7429 no NFSU2 |
| `op.engine.gta_fps_cap_60` | engine | Receita `gtasa` | `present.maxFps = 60` no conf | — | Física RenderWare no GTA SA |
| `op.engine.gta_memory_arg` | engine | Receita `gtasa` | Adiciona `-memory 1048576` | — | Estabilidade sob Wine |
| `op.wine.gta_media_overrides` | media | Receita `gtasa` | Overrides de áudio/mídia | — | Aborto de gstreamer |
| `op.patch.gta_mtld3d_renderer` | patch | Receita `gtasa` | Patch no d3d9.dll privado | — | Texturas no GTA SA |
| `op.plugin.nfsu2_widescreen` | plugin | Receita `nfsu2` | Provisiona WidescreenFix + ASI loader | — | Preparo sem plugins manuais |
| `op.plugin.gtasa_widescreen` | plugin | Receita `gtasa` | Provisiona WS Fix + hook vorbis | — | Preparo sem plugins manuais |
| `op.plugin.gtasa_silentpatch` | plugin | Receita `gtasa` | Provisiona SilentPatch | — | Mouse e timer sob Wine |

---

## 3. Exemplo de Produto: Composição para um Título Novo

Considere o exemplo hipotético mencionado pela pessoa usuária (*Need for Speed: Most Wanted* 2005):
1. **Inspeção do executável (`btp-peinfo.py`)**:
   - Arquitetura: `i386` (32-bit).
   - DLLs importadas: `d3d9.dll`, `kernel32.dll`, `user32.dll`.
   - Ano COFF: 2005.
2. **Avaliação pelo motor de operações (`btp-operations.py`)**:
   - `op.graphics.d3d9.mtld3d` é selecionada (aprendida no NFS e GTA).
   - `op.cpu.x87sidecar` é selecionada (aprendida no NFS e GTA).
   - `op.os.win7_legacy` é selecionada (aprendida no Splinter e NFS).
   - `op.storage.nfs_data_drive` **NÃO é selecionada** (específica da receita de NFSU2).
   - `op.engine.gta_fps_cap_60` **NÃO é selecionada** (específica da RenderWare do GTA).
   - `op.patch.gta_mtld3d_renderer` **NÃO é selecionada** (específica do GTA).
3. **Resultado**:
   O jogo recebe a combinação exata das fundações gráficas, de CPU e de sistema operacional comprovadas, sem herdar hacks desnecessários de títulos não-relacionados.

---

## 4. Precedência das Receitas e Rastreabilidade

Quando o hash do executável corresponde a uma receita homologada (em `scripts/game-profiles.json`):
- A receita tem **precedência estrita** sobre sugestões puramente genéricas.
- A preparação gera em tempo de execução:
  - `Registros/CompatibilityPlan.json`: parâmetros de configuração efetivos e regras avaliadas.
  - `Registros/OperationsPlan.json`: lista ordenada das operações executadas, componentes provisionados e backups criados.
  - `Registros/GameProfile.json`: metadados da receita, hash do executável e integridade do arquivo de origem.
- O processo é 100% reproduzível e reversível.
