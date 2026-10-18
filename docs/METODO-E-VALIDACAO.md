# Método local e validação — 17/10/2026

> Atualização18/10/2026: o BTP0.2.0 tem interface em português/inglês, atualizador Sparkle e provedor independente de runtime. Os resultados e os limites novos estão em [Validação0.2.0](VALIDATION-0.2.0.md). As referências a doador e à versão0.1.2 abaixo são históricas; as novas receitas ainda não tiveram uma partida confirmada.

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

O diagnóstico chegou a uma receita experimental que abriu o menu e o tutorial em aplicativo independente: Windows 7 para o executável, carregador `version.dll` nativo, FusionFix oficial e `WindowedMode=1`. Um teste posterior removeu o identificador de áudio acrescentado no clone e restaurou `RunValidation=True`: o menu continuou abrindo. Portanto esse ajuste manual de registro não faz parte da receita final. O `SkipSystemDetection` do FusionFix evita a detecção incompatível.

No app de teste, a cena do café e o menu PAUSE responderam aos comandos; o tutorial avançou até o objetivo de entrar na área do estande. Uma amostra de 29,745 s da cena inicial, com configuração mínima de diagnóstico, teve 54 intervalos, média 59,997 FPS e intervalo 58,140–62,044 FPS. São médias por intervalo, não mínimo por quadro nem resultado de toda a campanha. Não há comprovação de 4K/60.

O perfil incorporado à preparação aceita apenas o SHA256 da edição testada, verifica o ZIP do FusionFix antes de extrair, impede caminhos fora da cópia do jogo, guarda arquivos substituídos e restaura alterações se uma escrita falhar. Mantém o executável original. A versão do pacote é fixada pelo checksum; atualizações do projeto terceiro exigem nova revisão.

A API gráfica continua Metal; OpenGL ajudou no diagnóstico. As tentativas `debug.capsAll=true`, identidade Nvidia e biblioteca modificada do GTA não resolveram o problema inicial. O primeiro teste FusionFix não carregava a ASI porque o `version.dll` estava configurado como builtin. Conferir a biblioteca realmente carregada foi essencial.

A preparação automática pela pasta original também foi executada: o empacotador criou e assinou outro app, que chegou ao menu, abriu a história e exibiu o café; Escape mostrou PAUSE. Esse teste separado confirma o fluxo pasta → perfil → app, além do primeiro app de diagnóstico. A cópia instalada foi atualizada com backup, reabriu a história salva e mostrou a cena do café e PAUSE em 1280 × 720. Ainda faltam confirmar áudio ouvido, controle físico e uma sessão prolongada da campanha.

## O que os testes do BTP comprovam

- Build Swift arm64, sintaxe dos scripts, assinatura ad hoc e ZIP extraído verificados.
- O empacotador genérico recusa sobreposição com o runtime doador antes de alterar arquivos.
- O app é montado em staging; falhas de configuração ou assinatura preservam o app anterior; falha na troca tenta restaurá-lo. A versão substituída recebe backup.
- Sete cenários automatizados do empacotador passaram: colisão direta, colisão por link, falha do Wine, falha do wineserver, falha de assinatura, falha de instalação e instalação com backup. Esses testes usam substitutos de runtime/assinatura: verificam o empacotador, não jogos.
- Quatro testes do perfil Conviction cobrem rejeição de edição desconhecida, caminho malformado de ZIP, preservação da qualidade/executável e restauração após falha de escrita.
- A interface distingue **Preparado**, arquivos presentes, limite sugerido e FPS medido.

## Limites para distribuição

O fluxo público ainda é experimental. O runtime depende de uma origem local preparada; hoje a origem padrão é o app NFS já instalado. Ao tentar substituir esse mesmo doador, o empacotador bloqueia a ação e o preserva. Falta um runtime independente, versionado e provisionado com suas licenças.

O script legado GTA depende de componentes locais em `patches/gtasa`, que não fazem parte da distribuição pública. Não é um instalador universal para qualquer edição GTA. Scripts específicos legados precisam receber a mesma proteção de staging do fluxo genérico antes de recomendar recodificação de apps funcionais. A pasta portátil original, o app instalado e os saves são coisas diferentes e devem ter backup próprio.

A versão atual pode organizar e preparar ambientes locais para testes, mas não pode garantir que qualquer pasta de jogo se torne jogável com um botão. Para evoluir esse fluxo: detecção de versão e dependências → perfil específico → cópia isolada → preparação → validação de partida → registro reproduzível → entrega do app.

## Repouso durante testes

Bloqueios temporários de repouso devem ter prazo de expiração. Ao terminar ou pausar, encerrar jogos de teste e remover a própria asserção. O renderizador do jogo também pode impedir que a tela apague; parar somente `caffeinate` não resolve se a partida de teste continuar aberta.
