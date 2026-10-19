# BTP 0.2.4 — Rosetta e primeiro uso

## O que mudou

- Antes do preparo, o BTP testa a execução de código Intel.
- Se o Rosetta estiver ausente, oferece **Instalar e continuar** ou **Agora não**.
- A autorização abre um helper Intel inerte pelo LaunchServices, para que o macOS apresente o instalador oficial da Apple. Rosetta não é redistribuída e o BTP não aceita os termos por você.
- Só continua o preparo depois de testar novamente a execução Intel. Cancelamento/falha permanece recuperável.
- Falhas no preparo mostram **Tentar novamente**, em vez de **Abrir jogo**.
- Janela redimensionável a partir de 780 × 470 pontos; identidade visual mantida.
- Português e inglês.

## Verificações

39 testes automatizados passaram, incluindo um teste nativo com cinco cenários da instalação (já disponível, instalação/verificação, cancelamento, erro e helper ausente). O teste de empacotamento também executa sete cenários transacionais. Build Swift arm64 e helper x86_64 assinados/verificados. Janela aberta e ampliada pela interface de 780 × 502 para 1054 × 664 pontos incluindo a barra de título.

## Limites

Este Mac já tem Rosetta. O diálogo oficial e uma primeira instalação real em outro Mac sem Rosetta não foram reproduzidos nesta rodada; a pessoa que relatou a falha precisa confirmar a nova preparação. Não desinstalamos o componente do sistema para simular esse cenário. Não há nova alegação de FPS/jogabilidade. As receitas de jogos não foram alteradas; a validação anterior de partidas está em [0.2.3](VALIDATION-0.2.3.md). O app continua com assinatura ad hoc, sem notarização Apple.
