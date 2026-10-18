<div align="center">

# ⚡ Breaking the Pattern (BTP)

![Ícone do Breaking the Pattern](assets/icon.png)

### Prepare aplicativos de jogos Windows para testar no Mac com Apple Silicon
*BTP HyperMetal Engine • BTP Neural Silicon Accelerator • Zero-Clutter APFS Storage Engine*

[![macOS](https://img.shields.io/badge/macOS-Apple%20Silicon-blue?style=for-the-badge)](https://github.com/WennyLife/breaking-the-pattern)
[![Compatibilidade](https://img.shields.io/badge/Compatibilidade-Wine%20%2B%20Metal-00b4d8?style=for-the-badge)](#como-funciona)
[![Status](https://img.shields.io/badge/Status-Experimental-orange?style=for-the-badge)](#estado-dos-jogos)

**Uma interface macOS para organizar jogos próprios, preparar seus ambientes de compatibilidade e criar atalhos `.app`. Cada jogo precisa ser testado: gerar o aplicativo não confirma que uma partida funciona.**



</div>

## Como funciona

O launcher e a interface BTP são aplicativos macOS escritos em Swift. O jogo continua sendo o executável de Windows; o BTP não recompila seu código em uma versão nativa para Apple Silicon.

- **Wine** fornece a compatibilidade com APIs de Windows. O runtime local auditado deriva do build `cx-26.3.0-9` de [athei/wine-build](https://github.com/athei/wine-build).
- **Rosetta** executa o código Intel no Apple Silicon. O [x87sidecar](https://github.com/athei/x87sidecar) complementa esse caminho para operações x87 em perfis compatíveis.
- **Metal** é a API gráfica do Mac. Para os perfis Direct3D 9 validados localmente, [mtld3d](https://github.com/athei/mtld3d) traduz as chamadas gráficas para Metal. Outros jogos e APIs exigem configuração e validação próprias.
- **Correções específicas**, como Widescreen Fix e suporte a controles, dependem da versão do jogo e dos componentes presentes no ambiente local.

Os nomes **BTP HyperMetal Engine** e **BTP Neural Silicon Accelerator** são rótulos do projeto para integrar esses componentes de terceiros. “Neural” não indica uso do Neural Engine da Apple nem um acelerador de hardware proprietário.

**Zero-Clutter APFS Storage Engine** identifica o uso de clonagem APFS quando disponível. Clones podem compartilhar blocos inicialmente; alterações, caches, prefixos e backups consomem espaço. Não há garantia de zero bytes adicionais.

## Estado dos jogos

Situação registrada em **17 de outubro de 2026**, no Mac de desenvolvimento com Apple M5 Pro. “Relatado jogável” representa o teste do usuário; não cobre todas as missões, versões do jogo ou outros Macs.

| Jogo | Executável | Evidência atual | FPS e próximos testes |
| :--- | :--- | :--- | :--- |
| **Need for Speed Underground 2** | `SPEED2.EXE` | Usuário confirmou que está jogável | Há medições locais acima de 60 FPS; não estabelecem mínimo sustentado ou desempenho garantido em outros Macs. |
| **Grand Theft Auto: San Andreas** | `gta_sa.exe` | Usuário confirmou que está jogável | Manter **limite máximo de 60 FPS**: o usuário relatou problemas acima disso. Limite de 60 confirmado no menu; botões do controle ainda precisam de teste físico numa partida. |
| **Splinter Cell: Conviction** | `Conviction_game.exe` | Cena inicial e tutorial observados em app independente | Perfil experimental Metal em janela + FusionFix para uma edição identificada por SHA256. Amostra de diagnóstico de 30 s perto de 60 FPS; campanha completa, áudio e controle físico ainda pendentes. |

Outros perfis e o fluxo genérico são experimentais. A existência de um preset ou a detecção de um `.exe` não comprova compatibilidade. Não há promessa de suporte a qualquer jogo DirectX 9, de 4K, de 120/155 FPS ou de funcionamento em todos os chips M1–M5.

## FPS: limite, medição e jogabilidade

O cartão **Limite sugerido** mostra uma sugestão do perfil. A taxa de atualização da tela e o modelo do chip não determinam o FPS que o jogo conseguirá renderizar. Confirme a configuração aplicada e meça uma partida em primeiro plano.

O contador é um aplicativo separado com adaptadores para registros WineD3D e Metal HUD. Ele calcula médias por intervalo; não representa mínimo por quadro, “1% low” ou uma medição universal de qualquer jogo. Na versão local auditada, **Command + Option + 9** mostra ou oculta o painel.

Como evidência de diagnóstico, o registro do NFS de 17/10/2026 às 18:01 contém 115 médias por intervalo entre 50,25 e 115,62 FPS, com média 100,29 FPS. A sessão GTA das 18:08 contém 34 médias entre 49,06 e 52,01 FPS, com média 51,39 FPS. Esses registros não têm uma rota de gameplay comparável documentada e não servem como benchmark de “FPS cravado”.

Os antigos números promocionais de 4K/60, 120 e 155 FPS foram retirados por não terem validação reproduzível suficiente. Testes futuros devem registrar jogo/versão, runtime, resolução renderizada, qualidade, limite, duração e trecho jogado.

## Como usar

1. **Adicione a pasta da sua cópia do jogo.** O BTP procura o executável e os caminhos exigidos pelo perfil.
2. **Se uma mídia de instalação compatível for detectada**, use a etapa de extração. O suporte depende do formato e da organização da mídia; a extração não é universal.
3. **Clique em BREAK para preparar o app.** Para a edição Conviction identificada pelo perfil, o BTP baixa o FusionFix oficial com checksum fixo, guarda as configurações anteriores e usa Metal em janela. Outras edições precisam de validação própria.

    O estado **Preparado** indica que a preparação terminou ou que um app existente foi encontrado. Não equivale a “jogável verificado”.
4. **Abra o jogo e teste.** Verifique carregamento, imagem, áudio, teclado/controle e uma partida de pelo menos um minuto. Saia normalmente e confirme que as opções e o progresso continuam disponíveis ao reabrir.

A checagem de arquivos verifica presença dos caminhos esperados. Ela não autentica cada arquivo, não garante integridade total e não é um antivírus. Tamanho de executável, sozinho, não identifica malware.

O método local e os limites da validação estão em [Método e validação](docs/METODO-E-VALIDACAO.md).

## Ambiente de desenvolvimento

- O ambiente verificado é um **Mac com Apple M5 Pro e macOS 26.7.1**. Compatibilidade com outros Macs ou versões do macOS ainda depende de teste.
- A interface pode ser compilada com Swift e as ferramentas de desenvolvimento da Apple. A versão mínima de compilação da interface não garante que o runtime do jogo funcione nessa mesma versão do macOS.
- Os scripts usam componentes de runtime locais. O fluxo existente obtém esses componentes de `~/Applications/Need for Speed Underground 2.app/Contents/Resources`; scripts que aceitam `BTP_DONOR_RESOURCES` permitem indicar outra origem preparada.
- Clonar o repositório não fornece um jogo, um ambiente Windows completo ou todos os componentes necessários. Prepare as dependências locais antes de usar o fluxo de build.
- Assinaturas locais ad hoc não equivalem a notarização Apple ou distribuição pública validada.

Os jogos e seus saves ficam em diretórios locais de dados; preserve esses arquivos antes de recriar um ambiente. Apps, prefixos e configurações gerados são artefatos de teste até que sua execução seja validada.

O script legado de GTA requer componentes fornecidos localmente em `patches/gtasa`, ausentes na distribuição pública. Preserve o aplicativo funcional e seus saves; a recodificação desse perfil ainda exige revisão.

## Código e componentes

A licença MIT do BTP cobre o código próprio do projeto. Wine, x87sidecar, mtld3d, correções e demais componentes mantêm suas licenças e atribuições. Arquivos comerciais de jogos, executáveis e saves devem ser fornecidos localmente pelo usuário e ficar fora de uma distribuição pública do projeto.

## ☕ Apoie o projeto

O BTP é um projeto experimental de compatibilidade de jogos de PC no Mac. Relatos reproduzíveis ajudam a separar preparação bem-sucedida de jogabilidade real.

<div align="center">

[![Doar via PayPal](https://img.shields.io/badge/Apoiar-PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL)

**Chave Pix / E-mail PayPal:** `uildsonaraujo@gmail.com`

[Repositório do projeto](https://github.com/WennyLife/breaking-the-pattern)

</div>
