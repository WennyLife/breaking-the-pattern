# ⚡ Breaking the Pattern — Português

[English](README.md) · [Publicações](https://github.com/WennyLife/breaking-the-pattern/releases)

**0.2.0 Preview · português e inglês · Mac Apple Silicon · macOS 15 ou posterior**

O ZIP/DMG0.2.0 foi gerado e verificado localmente; o envio público dos instaladores ainda está pendente. O feed fica sem ofertas até os pacotes assinados serem publicados.

O BTP prepara um aplicativo Mac e um ambiente de compatibilidade para a pasta de um jogo que você fornece. Ele obtém o próprio motor, confere os downloads por SHA-256 e aplica receitas por edição. Não precisa de um NFS doador nem de Xcode no Mac final.

O pacote vem **sem jogos, executáveis comerciais, saves, cracks ou prefixos pessoais**. Cada pessoa fornece sua própria cópia. O BTP não baixa jogos comerciais nem substitui seus executáveis.

1. Baixe o DMG ou ZIP atual e copie o BTP para a pasta Aplicativos local.
2. Selecione a pasta do jogo. Instale Rosetta pelo macOS se necessário. A primeira preparação baixa cerca de235 MB de componentes, que ocupam aproximadamente1,3 GB após extraídos.
3. Clique em **BREAK**. As receitas iniciais se limitam às edições testadas de **NFS Underground 2** e **GTA San Andreas**.
4. Abra o aplicativo gerado e teste imagem, som, comandos, partida e persistência do save. **Preparado** não equivale a todas as missões verificadas.

Troque o idioma em **BTP → Language / Idioma**: português, inglês ou idioma do Mac. Isso muda a ferramenta, não os arquivos de idioma do jogo.

## Atualização pelo aplicativo

Use **BTP → Atualizações…** ou a seta circular no cabeçalho. A verificação automática é opcional; você escolhe quando instalar e reabrir.

O Sparkle verifica a assinatura Ed25519 do pacote. Antes de prosseguir, o BTP guarda e verifica a versão anterior em `~/Library/Application Support/Breaking the Pattern/Backups/Updates/`. Atualizar a ferramenta não substitui apps de jogos, prefixos nem saves. Para usar uma receita nova num jogo existente, a preparação precisa ser feita deliberadamente.

## Escopo e limites reais

- NFSU2: receita Direct3D9→Metal/x87, Windows7 e caminho/registro coerentes em `C:\Games\NFSU2`.
- GTA SA: receita Metal/x87, renderizador ajustado em cópia e limite60 FPS, preservando os demais ajustes de qualidade.
- Edições aceitas: [`scripts/game-profiles.json`](scripts/game-profiles.json). Outras edições são recusadas antes da preparação. Os plugins já presentes na pasta são preservados; o download automático de todos os mods específicos ainda não está implementado.
- Splinter Cell: os apps locais continuam acessíveis, mas o suporte de preparação fica para atualização futura. A falha nas vozes permanece aberta.
- O motor independente iniciou um ambiente Windows limpo e executou um comando; os novos apps NFS/GTA passaram na assinatura, mas uma partida nova ainda não foi confirmada. O NFS em prefixo limpo apresentou falha de inicialização e continua em diagnóstico.
- Os NFS/GTA locais foram jogáveis. Isso não garante todas as missões, outros Macs ou4K/60. O BTP ainda não foi validado por uma instalação completa em outro Mac.
- Assinatura ad hoc local, sem notarização Apple. Não há garantia de primeira abertura sem intervenção em outro Mac.
- Use pasta Aplicativos local. Um teste em Documentos sincronizados falhou na troca do app; a mesma atualização assinada funcionou e reabriu numa pasta local de teste.

A interface é nativa em Swift, mas o jogo continua Windows, com Wine/Rosetta/tradução gráfica para Metal. O BTP não recompila o jogo em código nativo. “HyperMetal” e “Neural” são rótulos do projeto; não significam uso do Neural Engine da Apple.

O contador separado usa **Command + Option + 9**. As médias por intervalo dos adaptadores Wine/Metal não são mínimo por quadro nem suporte universal a qualquer jogo.

Detalhes de compilação e componentes: [README em inglês](README.md), [licenças](THIRD_PARTY.md), [método e validação](docs/METODO-E-VALIDACAO.md).
