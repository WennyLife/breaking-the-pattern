<div align="center">

# ⚡ Breaking the Pattern (BTP)

**Native 4K / Ultra-Wide 60–155+ FPS Classic Windows Gaming on Apple Silicon**  
*Direct Metal (`mtld3d`) • ARM64 `x87` Cooperative Acceleration • Zero-Space APFS Cloning*

[![License: MIT](https://img.shields.io/badge/License-MIT-emerald.svg)](LICENSE)
[![Platform: macOS Apple Silicon](https://img.shields.io/badge/Platform-Apple%20Silicon%20(M1--M5)-blue.svg)](#)
[![Graphics: Direct Metal](https://img.shields.io/badge/DirectX%209-Direct%20Metal%20(mtld3d)-cyan.svg)](#)
[![Donate PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-WennyLife-ea4aaa?logo=github)](https://github.com/WennyLife)

</div>

---

## 🎯 Por que "Breaking the Pattern"? / The Motivation

Desde que a Apple removeu o suporte a binários de 32 bits no macOS Catalina e migrou para a arquitetura ARM64 (Apple Silicon M1 a M5), rodar jogos clássicos de PC da era de ouro do DirectX 9 (2002–2011) tornou-se um desafio marcado por engasgos e perdas severas de desempenho:

1. **O Gargalo da FPU `x87` no Rosetta 2:** Jogos com física avançada de veículos e colisões (*GTA San Andreas*, *Need for Speed*, etc.) utilizam intensamente instruções `x87` de ponto flutuante de 80 bits. Como a arquitetura ARM não possui registradores de 80 bits nativos, a emulação padrão estrangula a CPU, derrubando o desempenho para **15–25 FPS**.
2. **Camadas Gráficas Legadas (OpenGL / MoltenVK):** A tradução de Direct3D 9 passando por OpenGL ou Vulkan intermediário gera *stutters*, latência e consumo desnecessário de bateria no macOS.
3. **Instaladores Antigos (.cab / InstallShield):** Muitos jogos de DVD de PC não possuem instalador nativo para Mac, obrigando o usuário a ter um computador com Windows para extrair os arquivos.

O **Breaking the Pattern** foi construído do zero para quebrar esse padrão:
- Transforma pastas de jogos clássicos em **aplicativos macOS nativos e independentes (`.app`)** com apenas 1 clique.
- **Zero Espaço Adicional (APFS Copy-on-Write):** Toda a clonagem de ambientes é feita através de referências de blocos APFS (`cp -Rc`), consumindo 0 bytes adicionais no seu SSD para arquivos inalterados.
- **Direct Metal (`mtld3d`):** Direct3D 9 traduzido diretamente para a API Metal da Apple, entregando tempos de renderização de **3.8 ms por quadro** e 60–155 FPS constantes.
- **Aceleração Cooperativa `x87sidecar`:** Descarrega a matemática de 80 bits para processos dedicados em núcleos paralelos do Apple Silicon.
- **Auto-Scale Inteligente de Monitor & Chip:** Detecta o chip presente (`M1` a `M5 Pro/Max`) e calibra automaticamente a resolução (incluindo telas Ultra-Wide 21:9 e 32:9) e o limite de quadros seguro.
- **Escudo Anti-Malware Heurístico:** Bloqueia automaticamente instaladores falsos, droppers .NET inflados com *binary padding* (>60MB) e trojans antes de qualquer tentativa de execução.

---

## 🎮 Lista de Jogos Testados & Suportados

| Jogo | Executável | Status | Resolução | Taxa de Quadros (Auto-Scale) | Tecnologias Injetadas |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Grand Theft Auto: San Andreas** | `gta_sa.exe` *(v1.0 US)* | 🟢 **Perfeito** | Até 4K / Ultra-Wide 21:9 | **60.0 FPS Cravados** *(Trava Física)* | Direct Metal + `x87sidecar` + SilentPatch + WidescreenFix + GInput (Controle) + No-Blur Patch |
| **Need for Speed Underground 2** | `SPEED2.EXE` | 🟢 **Perfeito** | Até 4K / Ultra-Wide 21:9 | **60 – 130+ FPS** *(Por Chip)* | Direct Metal + `x87sidecar` + WidescreenFix + XtendedInput + HUD de FPS (`Tecla 0`) |
| **Call of Duty: Black Ops** | `BlackOps.exe` | 🟢 **Suportado** | Até 4K / Ultra-Wide 21:9 | **60 – 155 FPS Liberado** | Direct Metal (`mtld3d`) + DX9 Pipeline + XInput Gamepad |
| **Need for Speed: Most Wanted (2005)**| `speed.exe` | 🟢 **Suportado** | Até 4K / Ultra-Wide 21:9 | **60 – 120 FPS** *(Por Chip)* | Direct Metal + `x87sidecar` + WidescreenFix + XtendedInput |
| **Need for Speed: Carbon** | `NFSC.exe` | 🟢 **Suportado** | Até 4K / Ultra-Wide 21:9 | **60 – 120 FPS** *(Por Chip)* | Direct Metal + `x87sidecar` + WidescreenFix |
| **Qualquer Jogo DirectX 9 (.exe)** | `*.exe` | 🟡 **Genérico** | Resolução da Tela | **60 – 120+ FPS** | Direct Metal (`mtld3d`) + Wrapper Automático |

---

## 📊 Benchmark Real (Need for Speed Underground 2 @ 3440×1440 Ultra-Wide)

Testado em **Apple M5 Pro (15-Core CPU, 16-Core GPU, 24 GB RAM Unified)** com todos os efeitos no máximo:

| Método / Backend | Resolução | Taxa de Quadros | Tempo de GPU | Uso de CPU Total |
| :--- | :--- | :--- | :--- | :--- |
| D9VK + KosmicKrisp (Vulkan) | 3440 × 1440 | **4 FPS** 🔴 | Injogável | — |
| WineD3D Padrão (OpenGL) | 3440 × 1440 | **22 – 35 FPS** 🟡 | ~28.0 ms | Gargalo em 1 core |
| **⚡ Breaking the Pattern (Trava 60Hz)** | **3440 × 1440** | **60.0 FPS Cravados** 🟢 | **3.85 ms (23% GPU)** | **~8.5% CPU** |
| **⚡ Breaking the Pattern (ProMotion 120Hz)**| **Retina 120Hz** | **120.0 FPS Cravados** 🟢 | **3.85 ms** | **~9.5% CPU** |
| **⚡ Breaking the Pattern (Ultra-Wide 155Hz)**| **3440 × 1440 @ 155Hz**| **103 – 130.6 FPS** 🟢 | **3.85 ms (40% GPU)** | **~10% CPU** |

---

## 🚀 Como Usar

1. **Baixe o Aplicativo:** Obtenha a versão compilada em [Releases](https://github.com/WennyLife/breaking-the-pattern/releases) ou compile diretamente com o script `./scripts/build.sh`.
2. **Arraste a Pasta do Jogo:**
   - Arraste a pasta descompactada do jogo ou a mídia do instalador Windows (`data1.cab` / `setup.exe`).
   - O aplicativo valida instantaneamente os executáveis e arquivos essenciais.
3. **Clique em `⚡ BREAK`:**
   - O Breaking the Pattern injeta o motor Direct Metal (`mtld3d`), os aceleradores de hardware e calibra os limites de FPS ideais para o seu Mac.
4. **Pronto!**
   - O jogo é transformado em um aplicativo nativo em `~/Applications/` e pode ser aberto diretamente pelo Spotlight, Launchpad ou pelo próprio Breaking the Pattern.
   - Pressione a **Tecla `0`** a qualquer momento durante a partida para ligar/desligar o HUD de FPS em tempo real.

---

## 🎮 Suporte a Controles (Gamepads)

Compatível nativamente com controles modernos via Bluetooth ou Cabo USB no macOS:
- **Xbox Wireless Controller** (Xbox Series X/S, Xbox One)
- **PlayStation DualSense** (PS5) & **DualShock 4** (PS4)
- **Nintendo Switch Pro Controller**

> *Dica:* Em jogos como *GTA San Andreas*, os botões clássicos do controle são mapeados e texturizados nativamente com a biblioteca `GInputSA`.

---

## 🛠️ Compilação a partir do Código-Fonte

Requisitos:
- macOS 14.0 Sonoma ou superior
- Apple Silicon Mac (M1, M2, M3, M4, M5 ou variantes Pro/Max/Ultra)
- Xcode Command Line Tools (`xcode-select --install`)

```bash
# Clone o repositório
git clone https://github.com/WennyLife/breaking-the-pattern.git
cd breaking-the-pattern

# Compile o app nativo
./scripts/build.sh

# Abra o aplicativo
open "build/Breaking the Pattern.app"
```

---

## ☕ Apoie o Projeto / Donate

O **Breaking the Pattern** é um projeto de código aberto, mantido com dedicação para preservar e elevar a experiência dos melhores jogos clássicos no macOS.

Se o projeto foi útil para você ou permitiu reviver seus jogos favoritos com gráficos e fluidez impecáveis no Mac, considere apoiar o desenvolvimento contínuo:

- ☕ **PayPal (Internacional & Brasil):**  
  👉 **[Clique aqui para doar via PayPal](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL)**  
  *(Chave / E-mail: `uildsonaraujo@gmail.com`)*

- ⭐ **GitHub:** Deixe uma estrela no repositório para ajudar na visibilidade da comunidade!

---

## ⚖️ Aviso Legal / Disclaimer

O **Breaking the Pattern** é uma ferramenta de compatibilidade e otimização de código aberto sob licença MIT. **Este repositório NÃO distribui arquivos protegidos por direitos autorais, imagens ISO comerciais, arquivos de mídia ou executáveis proprietários das desenvolvedoras.** Os usuários devem utilizar suas próprias cópias legítimas dos jogos.
