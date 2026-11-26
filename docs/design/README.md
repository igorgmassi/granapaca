# Design do GranaPaCá

Identidade visual e design das telas do app, em 12 partes. Cada parte é um arquivo nesta pasta.

O ponto de partida é o [briefing original](00-briefing.md). Onde o briefing e as partes divergem, valem as partes.

| Parte | Assunto | Status | Quem cuida |
|---|---|---|---|
| [1](01-revisao-das-decisoes.md) | Revisão das decisões do briefing | Pronta | Ajustes por PR |
| [2](02-design-tokens.md) | Design tokens em JSON e Dart | Pronta | Ajustes por PR |
| [3](03-mascote.md) | Mascote: folha de modelo, expressões e máquina de estados | Pronta, em refinamento | Igor |
| [4](04-logo-e-icone.md) | Logo e ícone do app | Pronta | Ajustes por PR |
| [5](05-componentes.md) | Biblioteca de componentes, com estados | Pronta | Ajustes por PR |
| [6](06-telas-a.md) | Telas A: primeiro acesso e Início | Pronta | Ajustes por PR |
| 7 | Telas B: extrato, detalhe, correção e Gastos | A fazer | Colaboração |
| 8 | Telas C: chat, nota fiscal, gasto em dinheiro, planejamento, alertas, configurações e demo | A fazer | Colaboração |
| 9 | Fluxos | A fazer | Colaboração |
| 10 | Guia de microcopy | A fazer | Colaboração |
| 11 | Checagem de acessibilidade | A fazer | Colaboração |
| 12 | Passagem para o Flutter | A fazer | Colaboração |

## Convenções

- Os nomes de cor e de token seguem o briefing: Caramelo, Paçoca (fundo), Cacau, Mata, Urucum, Milho, Rio, Jabuticaba e os demais.
- [Suposição] marca decisão tomada sem confirmação. [Conferir: fonte] marca fato externo a validar na documentação oficial antes de implementar.
- Contraste e daltonismo são medidos por script, nunca no olho.
- Prints e exemplos usam só dados fictícios, como todo o repositório.

## Como colaborar

Enquanto o PR #6 está aberto, o design mora na branch `docs/design-system`, e não na `main`.

1. Faça um fork do repositório.
2. Crie a sua branch a partir da `docs/design-system`, por exemplo `design/telas-b`.
3. Abra o PR para a `docs/design-system`, e não para a `main`. Uma parte por PR fica mais fácil de revisar.

**Para não pisar no trabalho da Paçoca:**

- Não edite `mascote/`, `03-mascote.md` nem `telas/pacoca-mini.json`. Este último é gerado pelo `mascote/ilustrada/recorte.mjs`.
- Nas telas, use a Paçoca que já existe: o `pacoca(nome, x, y, alt)` do `telas/kit.mjs` lê as 12 poses do `pacoca-mini.json`.
- Se precisar de uma pose nova, peça numa issue ou no PR em vez de desenhar.

**Para as Partes 7 a 12:**

- Reaproveite as peças de `telas/kit.mjs`, como já fazem as telas A. Siga o modelo de `gerar-telas-a.mjs`: um gerador por parte, com as telas nos temas claro e escuro.
- As cores, fontes e medidas vêm de `tokens/tokens.json`. Cor nova só entra pelo tokens, e depois de passar no `node docs/design/tokens/check-contrast.mjs`.
- Cada parte é um arquivo `NN-nome.md` nesta pasta, com a linha "Para regenerar" no topo, como as Partes 5 e 6. Atualize a tabela acima no mesmo PR.
- O que muda de verdade em relação ao briefing vai com uma justificativa curta, no estilo da [Parte 1](01-revisao-das-decisoes.md).
- Se um gerador usar alguma dependência, instale fora do Git com `npm install --no-save --prefix docs/design <pacote>`.
