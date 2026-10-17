# Método local e validação — 17/10/2026

## O que funcionou

NFS Underground 2 e GTA San Andreas continuam como executáveis de Windows dentro de aplicativos Mac independentes. A interface BTP prepara esses aplicativos; não precisa ficar aberta para jogar. Não há tradução automática do código-fonte do jogo nem uma compilação nativa dele.

O caminho local usado nos dois foi Wine `cx-26.3.0-9`, Rosetta, x87sidecar cooperativo e Direct3D 9 traduzido para Metal pelo mtld3d `v0.13.0`. Um pequeno launcher macOS inicia o processo com diretório de trabalho, ambiente e prefixo próprios. As versões e ajustes de cada jogo precisam ser preservados juntos: copiar apenas uma DLL não reproduz o resultado.

### Need for Speed Underground 2

- Prefixo separado, caminho Windows curto `C:\Games\NFSU2` e registros do jogo apontando para esse caminho. Copiar a pasta portátil exigiu configurar os caminhos que antes dependiam da instalação Windows.
- Widescreen Fix e NFSU XtendedInput para o Xbox; resolução local 3440 × 1440. O perfil ativo usa `FPSLimit=0`, `SingleCoreAffinity=1` e `WindowedMode=4`.
- A combinação Wine/sidecar cooperativo foi determinante para sair das falhas anteriores. O resultado pertence a esse conjunto de componentes, não à potência do chip sozinha.
- Nesta rodada nenhuma configuração de gráficos, executável ou qualidade do NFS foi alterada. A primeira abertura falhou; a segunda chegou à rua e o usuário confirmou som e comandos. Portanto a nova verificação confirma gameplay observado, não estabilidade absoluta.
- O usuário relatou cerca de 103 FPS em sessão anterior. Não houve uma nova rota comparável que permita prometer esse número sustentado.

### GTA San Andreas

- Preservada a preparação funcional feita no Antigravity: executável e componentes existentes, correções locais de compatibilidade, Widescreen Fix, SilentPatch e GInput. As modificações de executável/renderizador existentes não foram reaplicadas nesta rodada.
- Confirmado visualmente no menu do jogo: **limite de 60 FPS**, resolução 3440 × 1440, qualidade muito alta e antisserrilhado 8x. Nenhuma dessas opções foi alterada.
- O carregador estava iniciando duas cópias idênticas de `GInputSA.asi`: raiz e `scripts/`. A cópia da raiz e seu INI foram movidos para backup fora da pasta do jogo. O novo registro confirma uma única instância e consultas XInput bem-sucedidas ao controle no slot 0.
- O menu abriu normalmente após o ajuste. **O teste físico dos botões durante uma partida continua pendente.** A detecção XInput não substitui esse teste.
- O usuário já havia relatado gameplay funcional. Esta rodada não constitui um novo benchmark de 60 FPS sustentados nem teste de todas as missões.

## Splinter Cell Conviction

Continua sem gameplay verificado. Apresentar Windows 7 apenas para `Conviction_game.exe` removeu o aviso de sistema incompatível. Em clone isolado, fornecer o identificador do dispositivo CoreAudio ao DxDiag permitiu passar pela detecção de áudio. Isso não bastou: o caminho Metal encerra antes da partida; OpenGL manteve janela com imagem incorreta. O teste adicional `debug.capsAll=true` também encerrou em cerca de 12 segundos. Esse ajuste não foi incorporado ao aplicativo instalado.

O erro de áudio inicial e a falha posterior são etapas diferentes. Não aplicar todos os testes do clone como se fossem uma solução. Ainda é necessário localizar a razão exata do encerramento do motor do jogo e reproduzir uma partida.

## O que a versão BTP 0.1.1 comprova

- Build Swift arm64, sintaxe dos scripts, assinatura ad hoc e ZIP extraído verificados.
- O empacotador genérico recusa sobreposição com o runtime doador antes de alterar arquivos.
- O app é montado em staging; falhas de configuração ou assinatura preservam o app anterior; falha na troca tenta restaurá-lo. A versão substituída recebe backup.
- Sete cenários automatizados passaram: colisão direta, colisão por link, falha do Wine, falha do wineserver, falha de assinatura, falha de instalação e instalação com backup. Esses testes usam substitutos de runtime/assinatura: verificam o empacotador, não jogos.
- A interface distingue **Preparado**, arquivos presentes, limite sugerido e FPS medido.

## Limites para distribuição

O fluxo público ainda é experimental. O runtime depende de uma origem local preparada; hoje a origem padrão é o app NFS já instalado. Ao tentar substituir esse mesmo doador, o empacotador bloqueia a ação e o preserva. Falta um runtime independente, versionado e provisionado com suas licenças.

O script legado GTA depende de componentes locais em `patches/gtasa`, que não fazem parte da distribuição pública. Não é um instalador universal para qualquer edição GTA. Scripts específicos legados precisam receber a mesma proteção de staging do fluxo genérico antes de recomendar recodificação de apps funcionais. A pasta portátil original, o app instalado e os saves são coisas diferentes e devem ter backup próprio.

A versão atual pode organizar e preparar ambientes locais para testes, mas não pode garantir que qualquer pasta de jogo se torne jogável com um botão. Para evoluir esse fluxo: detecção de versão e dependências → perfil específico → cópia isolada → preparação → validação de partida → registro reproduzível → entrega do app.

## Repouso durante testes

Bloqueios temporários de repouso devem ter prazo de expiração. Ao terminar ou pausar, encerrar jogos de teste e remover a própria asserção. O renderizador do jogo também pode impedir que a tela apague; parar somente `caffeinate` não resolve se a partida de teste continuar aberta.
