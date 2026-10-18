# Inventário de Plugins e Dependências — NFSU2 e GTA SA

Data: 2026-10-18.
Este documento detalha o inventário de plugins e bibliotecas presentes nas cópias de validação do *Need for Speed Underground 2* e *Grand Theft Auto: San Andreas*, separando os componentes estritamente necessários para o funcionamento reproduzível daqueles opcionais/de conforto.

---

## 1. Need for Speed Underground 2 (`SPEED2.EXE`)

### Inventário da cópia de validação
Localização analisada: `/Users/lendaii/Library/Application Support/Need for Speed Underground 2/Game/`

| Arquivo | Tamanho | SHA256 | Identificação |
|---|---|---|---|
| `dinput8.dll` | 5.397.864 B | `7675b24a2e408349c8a59b87e3ae8724ad8a89eff21c96a9c109650a3c1316e0` | ThirteenAG Ultimate ASI Loader (x86) |
| `scripts/NFSUnderground2.WidescreenFix.asi` | 6.350.784 B | `8a94668103f64644e5c7fd79b33c0d29491fd1e7f95d4c679dfb9bb10bda9d54` | ThirteenAG Widescreen Fix |
| `scripts/NFSUnderground2.WidescreenFix.ini` | 4.057 B | — | Configuração de proporção, FOV e HUD |
| `scripts/NFSUnderground2.WidescreenFix.dat` | 5.736 B | — | Dados de calibração de HUD |
| `scripts/NFSU_XtendedInput.asi` | 43.520 B | `47c37f389e43e59018795df611abb657a033d0af9dd636dd85e3b111796592cc` | XtendedInput (Berkay Yigit / Xan1242) |
| `scripts/NFSU_XtendedInput.ini` | 9.497 B | — | Mapeamento de controles |

### Classificação e papel

1. **`dinput8.dll` (Ultimate ASI Loader)** — **NECESSÁRIO**
   - **Papel:** O executável importa `dinput8.dll`. O Wine carrega o arquivo local via `WINEDLLOVERRIDES="dinput8=n,b"`, interceptando chamadas e carregando os módulos `.asi` da pasta `scripts/`.
   - **Sintoma sem ele:** Nenhum plugin na pasta `scripts/` é carregado; o jogo roda em resolução padrão não-panorâmica (640×480 ou 800×600) e falha na verificação de CD caso não haja imagem de mídia montada.

2. **`NFSUnderground2.WidescreenFix`** — **NECESSÁRIO**
   - **Papel:** Permite resoluções modernas panorâmicas (16:9, 21:9), reposiciona e escala elementos da interface/HUD (velocímetro, mapa) e bypassa a checagem rígida de unidade de disco óptico.
   - **Sintoma sem ele:** Imagem distorcida/esticada, HUD esticado, resolução limitada às opções nativas antigas de 4:3, e dependência estrita de mídia física.
   - **Origem oficial:** [ThirteenAG/WidescreenFixesPack](https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/nfsu2/NFSUnderground2.WidescreenFix.zip) (SHA256: `791fcf486db6916642b02a51dd6ed786da7bdbd6c4ad7e207c36ba1f0a5cca59`). O pacote oficial já inclui tanto o `dinput8.dll` quanto o fix completo.

3. **`NFSU_XtendedInput`** — **OPCIONAL (Conforto)**
   - **Papel:** Oferece suporte nativo ao padrão XInput com gatilhos analógicos e ícones de controle modernos.
   - **Sintoma sem ele:** O jogo continua jogável perfeitamente com teclado ou DirectInput nativo do Wine.

---

## 2. Grand Theft Auto: San Andreas (`gta_sa.exe`)

### Inventário da cópia de validação
Localização analisada: `/Users/lendaii/Library/Application Support/Grand Theft Auto San Andreas/prefix-metal/drive_c/Games/GTASA/`

| Arquivo | Tamanho | SHA256 | Identificação |
|---|---|---|---|
| `vorbisFile.dll` | 5.418.336 B | `d5a059aa467a7a7127c8f6169f79fa63ff0f55986ee9eb2fd9a281bebf2aa2e6` | ThirteenAG Ultimate ASI Loader (x86 renomeado) |
| `vorbisHooked.dll` | 65.536 B | `a08923479000cec366967fb8259e0920b7aa18859722c7dda1415726bed4774f` | DLL original do jogo renomeada para encaminhamento |
| `scripts/GTASA.WidescreenFix.asi` | 5.110.264 B | `9f8a2b5c508010d0423ba9d712b203225a46a49998d5467f4a1bb9835580a513` | ThirteenAG Widescreen Fix |
| `scripts/GTASA.WidescreenFix.ini` | 2.039 B | — | Configuração de FOV e escala de radar |
| `scripts/SilentPatchSA.asi` | 396.288 B | `a95f9550175a8f41f68d24d93b34610fe5f6f486b9bf543438f698564543443b` | SilentPatch (CookiePLMonster) |
| `scripts/SilentPatchSA.ini` | 3.253 B | — | Configurações do patch |
| `scripts/GInputSA.asi` | 241.664 B | `600c01290ac9c071f9042dea55566555298f1949e3741d565707152d6d24d751` | GInput (Silent) |
| `scripts/GInputSA.ini` | 8.236 B | — | Mapeamento de botões de controle |

### Classificação e papel

1. **`vorbisFile.dll` (ASI Loader) + `vorbisHooked.dll`** — **NECESSÁRIO**
   - **Papel:** Como o GTA SA importa `vorbisfile.dll` para decodificação de áudio, a comunidade adota o Ultimate ASI Loader instalado como `vorbisFile.dll`. O arquivo original da Rockstar é renomeado para `vorbisHooked.dll` para que o loader encaminhe as chamadas de áudio legítimas.
   - **Sintoma sem ele:** Nenhum plugin `.asi` carrega; som quebra se a substituição não mantiver o encaminhamento.

2. **`SilentPatchSA` (CookiePLMonster)** — **NECESSÁRIO**
   - **Papel:** Corrige a resolução do timer de 14ms (que causa stutter e quebra de física mesmo a 30 FPS sem o patch), trava do ponteiro do mouse ao sair do menu para o jogo e erros críticos de vazamento de memória sob Wine.
   - **Sintoma sem ele:** Mouse frequentemente perde o foco e congela ao pausar o jogo; problemas na taxa de quadros e física.
   - **Origem oficial:** [CookiePLMonster/SilentPatch](https://github.com/CookiePLMonster/SilentPatch/releases/latest/download/SilentPatchSA.zip) (SHA256: `0837bbdc0548a4a952f924adefd2bb6eacc866407f153844fe1f56995668c42c`).

3. **`GTASA.WidescreenFix` (ThirteenAG)** — **NECESSÁRIO**
   - **Papel:** Corrige a proporção de tela widescreen, escala do radar circular (que de outra forma fica ovalado) e posicionamento das armas e legendas.
   - **Sintoma sem ele:** Imagem horizontalmente esticada e mira desalinhada.
   - **Origem oficial:** [ThirteenAG/WidescreenFixesPack](https://github.com/ThirteenAG/WidescreenFixesPack/releases/download/gtasa/GTASA.WidescreenFix.zip) (SHA256: `563078bfae5ad93be548d9378d4a97809762fb3a8dfdf0ef65e6023beadeb3ae`). O pacote já inclui `vorbisFile.dll`.

4. **`GInputSA` (Silent)** — **OPCIONAL (Controle)**
   - **Papel:** Mapeamento avançado para controles DualShock/Xbox com comandos modernos e vibração.
   - **Sintoma sem ele:** O jogo funciona perfeitamente com teclado e mouse ou com controles genéricos configurados no menu nativo.

---

## 3. Estratégia de Reprodução Automática no BTP

Quando uma pessoa usuária arrasta uma pasta limpa (sem os plugins) e aperta **BREAK**:
1. O BTP detecta se os arquivos essenciais estão presentes via `btp-components.py --check`.
2. Se ausentes, obtém o pacote oficial fixado por SHA256 do cache local (`~/Library/Caches/Breaking the Pattern/Downloads`) ou da URL oficial de release.
3. Valida a segurança do pacote (sem traversals, limites estritos de tamanho, integridade de checksum).
4. No GTA SA, antes de colocar `vorbisFile.dll`, move o arquivo original para `vorbisHooked.dll` (com backup em `Backups/Components/`).
5. Extrai os plugins necessários e registra a operação em `Registros/OperationsPlan.json`.
