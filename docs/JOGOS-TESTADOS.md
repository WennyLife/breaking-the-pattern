# Jogos testados e próximos candidatos

Atualizado em 24/10/2026. BTP prepara um ambiente de compatibilidade para jogos Windows no Mac Apple Silicon. Isso não é recompilação nativa do jogo. O BTP não inclui jogos.

## Resultados observados

| Jogo / edição | Evidência e limite do resultado |
|---|---|
| Need for Speed Underground 2, PC | Receita reproduzida em cópia independente; partida, som, comandos e reabertura do perfil confirmados pelo usuário. Outras edições e Macs precisam de teste próprio. |
| Grand Theft Auto: San Andreas, PC clássico | Receita reproduzida em cópia independente; partida, som e comandos confirmados pelo usuário. Manter limite de 60 FPS da configuração validada; não estender esse limite automaticamente a outros GTA. Não inclui a Definitive Edition. |
| Splinter Cell Conviction, instalação Complete testada | Em 22/10 o usuário confirmou gameplay funcionando, com relato de cerca de 60 FPS em partida e cerca de 30 FPS em algumas cutscenes. Não houve medição independente desses números nesta auditoria. Receita específica com FusionFix; reprodução completa em outra instalação/Mac continua pendente. |
| Call of Duty: Black Ops II, cópia testada | Não chegou a uma partida nos testes de inicialização. Investigação encerrada a pedido do usuário em 22/10. Não há suporte validado; a falha não comprova incompatibilidade de todas as edições. |

A confirmação de partida é diferente de campanha completa, todos os modos, multiplayer, mapeamento físico de todos os botões e estabilidade prolongada. Esses itens não estão integralmente certificados.

## Conferência do BTP em 24/10

- Instalação local: 0.2.6, build 13. Canal público consultado pelo próprio app: 0.2.4; nenhuma atualização instalada nesta auditoria.
- 40 testes automatizados passaram, incluindo perfis, operações, runtime, Rosetta e deduplicação da biblioteca.
- Sete cenários de empacotamento com arquivos fictícios passaram: colisões, falhas e preservação/restauração do app anterior. Não são partidas reais.
- Assinatura estrutural do app instalado verificada; isso não equivale a notarização Apple.
- Os 14 scripts e arquivos de configuração comparáveis embarcados coincidem com o código auditado.
- O Python embarcado leu os três executáveis reais da biblioteca com sucesso e sem mudar seus hashes. Isso valida a inspeção, não a integridade de todos os arquivos do jogo.
- Interface abriu; biblioteca mostrou três jogos sem duplicação; seleção de Conviction, abertura/cancelamento do seletor de pasta e consulta ao atualizador funcionaram.
- Nenhuma nova partida, preparação integral ou instalação em outro Mac foi realizada nesta auditoria. Os relatos anteriores e a confirmação atual do usuário fundamentam o status de jogabilidade.

## Próximos candidatos — ainda não validados no BTP

Esta é uma ordem de investigação, não uma lista de suporte. A existência de correções comunitárias ajuda a montar uma receita específica; não prova que o jogo abra diretamente no BTP. Não copie DLLs/ASI de um título para outro só por serem da mesma época.

| Prioridade | Jogo, versão PC original | Motivo para testar |
|---|---|---|
| 1 | Need for Speed Most Wanted (2005) | Continuidade do trabalho com NFS; possui Widescreen Fix específico. Não confundir com Most Wanted (2012). |
| 2 | Need for Speed Carbon | Outro candidato NFS com correção própria de widescreen e comandos. |
| 3 | Need for Speed Underground (primeiro) | Próximo do título já testado e com Widescreen Fix próprio. |
| 4 | Grand Theft Auto: Vice City, clássico | SilentPatch e Widescreen Fix específicos; aprendizado do GTA SA pode orientar o teste, sem reutilizar seus binários. |
| 5 | Grand Theft Auto III, clássico | Também possui SilentPatch e correções de widescreen próprias. |
| 6 | Splinter Cell: Chaos Theory | Possui correção específica; o sucesso de Conviction não garante o mesmo caminho para este título. |
| 7 | Max Payne 2 | Possui Widescreen Fix; candidato adicional para avaliar o ambiente de compatibilidade legado. |
| 8 | Bully: Scholarship Edition | SilentPatch próprio; investigar estabilidade e limite de quadros separadamente. |

Fontes primárias para a existência dos componentes: [Widescreen Fixes Pack / FusionFix](https://github.fusionfix.io/wfp), [SilentPatch para GTA III, Vice City e San Andreas](https://github.com/CookiePLMonster/SilentPatch), [SilentPatchBully](https://github.com/CookiePLMonster/SilentPatchBully). A seleção de prioridade é nossa hipótese de engenharia, não uma alegação desses projetos de suporte ao BTP/macOS.

Para cada candidato: usar uma cópia separada, registrar edição/hash e configuração, preparar, abrir, jogar com áudio e comandos, salvar e reabrir. Só então promover a receita a suporte validado.
