<div align="center">

# ⚡ Breaking the Pattern (BTP)

![Breaking the Pattern](assets/banner.png)

### Jogos Clássicos de PC Windows a 60–155+ FPS Nativos no Apple Silicon
*Direct Metal (`mtld3d`) • Aceleração Cooperativa ARM64 `x87sidecar` • Clonagem Zero-Space via APFS*

<br/>

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue?style=for-the-badge&logo=apple)](https://github.com/WennyLife/breaking-the-pattern)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%20%7C%20M2%20%7C%20M3%20%7C%20M4%20%7C%20M5-6f42c1?style=for-the-badge&logo=apple)](https://github.com/WennyLife/breaking-the-pattern)
[![Gráficos](https://img.shields.io/badge/DirectX%209-Direct%20Metal%20(mtld3d)-00b4d8?style=for-the-badge)](#)
[![Física](https://img.shields.io/badge/FPU%20x87-Rosetta%20Sidecar%20ARM64-orange?style=for-the-badge)](#)
[![Licença](https://img.shields.io/badge/Licen%C3%A7a-MIT-green?style=for-the-badge)](LICENSE)
[![Doações](https://img.shields.io/badge/Apoiar-PayPal-00457C?style=for-the-badge&logo=paypal)](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL)

<br/>

**Transforme qualquer instalador ou pasta de jogo clássico de Windows em um aplicativo macOS nativo e independente (`.app`), rodando com gráficos Metal direto na GPU, física calibrada a 60–155 FPS e suporte completo a controles de Xbox e PlayStation!**

<br/>

![Interface do Breaking the Pattern](assets/app_screenshot.png)

</div>

---

## 🎯 Por que "Breaking the Pattern"? / The Motivation

Desde que a Apple descontinuou o suporte a aplicativos de 32 bits no macOS Catalina e migrou os Macs para a arquitetura ARM64 (Apple Silicon M1 a M5), rodar os clássicos da era de ouro do PC (2002–2011) tornou-se uma experiência frustrante:

1. **O Gargalo da FPU `x87` no Rosetta 2:** Jogos clássicos com física apurada de suspensão e veículos (*GTA San Andreas*, *Need for Speed*, etc.) utilizam instruções matemáticas `x87` de 80 bits. Como a arquitetura ARM não possui registradores de 80 bits nativos, a tradução do Rosetta 2 estrangula a CPU, derrubando o desempenho para **15–25 FPS**.
2. **Camadas Gráficas Legadas (OpenGL / MoltenVK):** Tradutores convencionais de DirectX 9 que passam por OpenGL ou Vulkan intermediário sofrem com engasgos severos (*stutters*), atraso de comandos e alto consumo de energia.
3. **Instaladores Antigos (.cab / InstallShield):** A maioria dos downloads de jogos de PC antigos vem no formato de mídia de instalação (`setup.exe`, `data1.cab`, `data1.hdr`), impedindo que usuários de Mac consigam sequer extrair os arquivos sem um PC com Windows.

O **Breaking the Pattern** foi arquitetado para quebrar esse padrão de ponta a ponta:
- **Direct Metal (`mtld3d`):** Direct3D 9 traduzido diretamente para a API Metal da Apple, entregando tempos de renderização de apenas **3.8 ms por quadro** e estabilidade total em 60–155 FPS.
- **Aceleração Cooperativa `x87sidecar`:** Descarrega as operações de ponto flutuante de 80 bits para processos nativos ARM64 em núcleos paralelos da CPU.
- **Zero Espaço em Disco Adicional (APFS Copy-on-Write):** Toda a clonagem é feita por ponteiros de blocos (`cp -Rc`). O jogo não consome nenhum giga extra no seu SSD!
- **Auto-Scale Inteligente por Chip & Monitor:** Detecta se você está em um MacBook Air M1 a 60Hz, em uma tela Retina ProMotion de 120Hz ou em um monitor Ultra-Wide a 155Hz+, calibrando a física e a resolução nativamente.
- **Escudo Anti-Malware Heurístico:** Analisa os binários antes da execução e bloqueia trojans camuflados com *binary padding* (>60MB) para proteger seu Mac.

---

## 🚀 Como Usar: O Fluxo Inteligente em 2 Cenários

Muitas vezes você baixa um jogo clássico e ele não vem como uma pasta pronta, mas sim como um **instalador de Windows** (arquivos `.cab` e `setup.exe`). O Breaking the Pattern resolve ambos os casos:

### 📦 Cenário 1: Se você baixou o Instalador Windows (`setup.exe` + `data1.cab` / Imagem de Disco)
*Você não precisa de um PC com Windows para instalar seus jogos! O Breaking the Pattern descompacta e monta o jogo nativamente:*

1. **Arraste a pasta do instalador** (ou a imagem `.iso` montada) para a área pontilhada do Breaking the Pattern.
2. **Passo 1 — Instalação Nativa no Mac (`📦 PASSO 1: INSTALAR JOGO NO MAC`):**
   - O aplicativo detecta a mídia de instalação e habilita o botão azul de extração.
   - O extrator integrado (`unshield`) descompacta todos os bancos de áudio (`SFX`, rádios), texturas (`.txd`), modelos 3D (`models/`) e extrai o executável original do jogo sem travar o macOS.
3. **Passo 2 — Otimização e Codificação (`⚡ PASSO 2: BREAK`):**
   - Concluída a extração, o botão se transforma no comando **`⚡ PASSO 2: BREAK`**.
   - Ao clicar, o motor injeta o Direct Metal (`mtld3d`), o acelerador `x87sidecar`, correções de Widescreen (16:9, 21:9 ou 32:9), o patch de remoção de Motion Blur e o suporte a controles modernos.
4. **Passo 3 — Jogar (`🎮 JOGAR AGORA`):**
   - O botão se ilumina em verde! O jogo agora é um aplicativo nativo em `~/Applications/` e pode ser aberto diretamente pelo Spotlight, Launchpad ou pela própria interface.

---

### 🎮 Cenário 2: Se você já tem a Pasta do Jogo Pronta (com o executável `.exe`)
*(Exemplos: Need for Speed Underground 2, Call of Duty: Black Ops, etc.)*

1. **Arraste a pasta do jogo** para o Breaking the Pattern.
2. O validador confirma a integridade dos arquivos e pula diretamente para o **Passo 2 (`⚡ BREAK`)**.
3. **Clique em `⚡ BREAK`:** Em poucos segundos, o ambiente é clonado via APFS (sem duplicar espaço), o Direct Metal é ativado e o aplicativo nativo de Mac é gerado.
4. **Clique em `🎮 JOGAR AGORA`** e divirta-se!

---

## 📐 Arquitetura do Sistema

```mermaid
flowchart TD
    subgraph Entrada["📥 Entrada do Usuário"]
        Installer["📦 Instalador Windows (.CAB / Setup.exe)"]
        GameFolder["📂 Pasta do Jogo com Executável (.EXE)"]
    end

    subgraph BTP["⚡ Motor Breaking the Pattern"]
        Scanner["🛡️ Escudo Anti-Malware & Validador Heurístico"]
        Unshield["📦 Extrator Nativo InstallShield (unshield)"]
        APFS["⚡ Clonagem Instantânea APFS (Zero Espaço Extra)"]
        Metal["💎 Direct Metal (mtld3d Direct3D 9 -> Apple Metal)"]
        Sidecar["🚀 Acelerador FPU x87sidecar (ARM64 Paralelo)"]
        Widescreen["🖥️ Calibrador de Tela (4K / Ultra-Wide 60–155 FPS)"]
        Gamepad["🎮 Injetor de Gamepad (Xbox Series / PS5 DualSense)"]
    end

    subgraph Saida["🎮 macOS Nativo"]
        App["Aplicativo Standalone em ~/Applications/ (.app)"]
        Play["60–155 FPS Cravados • HUD de FPS (Tecla 0) • 3.8ms GPU"]
    end

    Installer --> Scanner
    GameFolder --> Scanner
    Scanner -->|Se for Instalador .CAB| Unshield
    Unshield --> APFS
    Scanner -->|Se for Jogo Pronto| APFS
    APFS --> Metal
    APFS --> Sidecar
    Metal --> Widescreen
    Sidecar --> Gamepad
    Widescreen --> App
    Gamepad --> App
    App --> Play

    classDef input fill:#1f2937,stroke:#4b5563,stroke-width:2px,color:#fff;
    classDef btp fill:#111827,stroke:#f59e0b,stroke-width:2px,color:#fff;
    classDef output fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    class Entrada input;
    class BTP btp;
    class Saida output;
```

---

## 🎮 Jogos Testados & Perfis Nativos

| Jogo | Executável | Status | Resolução | Taxa de Quadros (Auto-Scale) | Recursos & Modificações Injetadas |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Grand Theft Auto: San Andreas** | `gta_sa.exe` *(v1.0 US)* | 🟢 **Perfeito** | Até 4K / Ultra-Wide 21:9 | **60.0 FPS Cravados** *(Trava Física)* | Direct Metal + `x87sidecar` + SilentPatch + WidescreenFix + GInput (Controle) + No-MotionBlur |
| **Need for Speed Underground 2** | `SPEED2.EXE` | 🟢 **Perfeito** | Até 4K / Ultra-Wide 21:9 | **60 – 130+ FPS** *(Por Chip)* | Direct Metal + `x87sidecar` + WidescreenFix + XtendedInput + HUD de FPS (`Tecla 0`) |
| **Call of Duty: Black Ops** | `BlackOps.exe` | 🟢 **Suportado** | Até 4K / Ultra-Wide 21:9 | **60 – 155 FPS Liberado** | Direct Metal (`mtld3d`) + DX9 Pipeline + Suporte a XInput Gamepad |
| **Need for Speed: Most Wanted (2005)**| `speed.exe` | 🟢 **Suportado** | Até 4K / Ultra-Wide 21:9 | **60 – 120 FPS** *(Por Chip)* | Direct Metal + `x87sidecar` + WidescreenFix + XtendedInput |
| **Need for Speed: Carbon** | `NFSC.exe` | 🟢 **Suportado** | Até 4K / Ultra-Wide 21:9 | **60 – 120 FPS** *(Por Chip)* | Direct Metal + `x87sidecar` + WidescreenFix |
| **Qualquer Jogo DirectX 9 (.exe)** | `*.exe` | 🟡 **Genérico** | Resolução Nativa | **60 – 120+ FPS** | Direct Metal (`mtld3d`) + Wrapper de Compatibilidade |

---

## 📊 Benchmark Real (Need for Speed Underground 2 @ 3440×1440 Ultra-Wide)

Testado em um **MacBook Pro com Apple M5 Pro (15-Core CPU, 16-Core GPU, 24 GB RAM Unified)** com todos os efeitos no máximo:

| Método / Camada Gráfica | Resolução | Taxa de Quadros | Tempo de GPU | Uso de CPU Total |
| :--- | :--- | :--- | :--- | :--- |
| D9VK + KosmicKrisp (Vulkan) | 3440 × 1440 | **4 FPS** 🔴 | Injogável | — |
| WineD3D Padrão (OpenGL) | 3440 × 1440 | **22 – 35 FPS** 🟡 | ~28.0 ms | Gargalo em 1 core |
| **⚡ Breaking the Pattern (Trava 60Hz)** | **3440 × 1440** | **60.0 FPS Cravados** 🟢 | **3.85 ms (23% GPU)** | **~8.5% CPU** |
| **⚡ Breaking the Pattern (ProMotion 120Hz)**| **Retina 120Hz** | **120.0 FPS Cravados** 🟢 | **3.85 ms** | **~9.5% CPU** |
| **⚡ Breaking the Pattern (Ultra-Wide 155Hz)**| **3440 × 1440 @ 155Hz**| **103 – 130.6 FPS** 🟢 | **3.85 ms (40% GPU)** | **~10% CPU** |

---

## 🎮 Suporte a Controles (Gamepads)

Compatível nativamente com controles modernos via Bluetooth ou Cabo USB no macOS:
- **Xbox Wireless Controller** (Xbox Series X/S, Xbox One)
- **PlayStation DualSense** (PS5) & **DualShock 4** (PS4)
- **Nintendo Switch Pro Controller**

> *Dica:* Em jogos como *GTA San Andreas*, os botões e texturas clássicas do controle são injetados automaticamente pela biblioteca `GInputSA`.  
> Pressione a **Tecla `0`** a qualquer momento durante a partida para ligar ou desligar o medidor de FPS em tempo real!

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

O **Breaking the Pattern** é um projeto de código aberto, mantido com dedicação para preservar e elevar a experiência dos melhores jogos clássicos de PC no ecossistema Mac Apple Silicon.

Se o projeto foi útil para você ou permitiu reviver seus jogos favoritos com gráficos e fluidez impecáveis no Mac, considere apoiar o desenvolvimento:

<div align="center">

[![Doar via PayPal](https://img.shields.io/badge/Doar_via_PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL)

**Chave Pix / E-mail PayPal:** `uildsonaraujo@gmail.com`

⭐ **Não se esqueça de deixar uma estrela no repositório!**

</div>

---

## ⚖️ Aviso Legal / Disclaimer

O **Breaking the Pattern** é uma ferramenta de compatibilidade e otimização de código aberto sob licença MIT. **Este repositório NÃO distribui arquivos protegidos por direitos autorais, imagens ISO comerciais, arquivos de mídia ou executáveis proprietários das desenvolvedoras.** Os usuários devem utilizar suas próprias cópias legítimas dos jogos.
