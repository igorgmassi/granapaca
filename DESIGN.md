# Design do GranaPaCá

Resumo das decisões visuais que valem para todo o app. O detalhe de cada uma está em [`docs/design`](docs/design/README.md), e os valores estão em [`docs/design/tokens/tokens.json`](docs/design/tokens/tokens.json).

## Mundo visual

- **Conceito:** a paca que junta tudo. O app é a toca da Paçoca, que traz a grana de todos os bancos pra cá.
- **Clima:** quente e brasileiro, com cores de fruta e de mata, longe do azul de banco.
- **Regra de ouro:** diversão nos detalhes, clareza no que importa. Navegação, números e botões são sérios. A graça mora na Paçoca, nas mensagens, nos estados vazios e nas comemorações.
- **Primeiro acesso:** a "Trilha até a toca", uma caminhada pela mata do fim de tarde até a noite, no ritmo do Duolingo e sem gamificação que cobra.

## Cor

- Paleta "Mata e Fruta" sobre o Material 3. Caramelo é a marca (`primary`), e Paçoca é o fundo (`surface`).
- Gasto na cor do texto, com "−". Receita em Mata, com "+". Vermelho (Urucum) só para alerta e erro.
- Essencialidade é uma escala de Caramelo, sempre com o nome do nível ou as pintas (●●●, ●●○, ●○○).
- Gráficos usam 8 cores fixas por grupo, na ordem da rosca. A cor segue o grupo, nunca a posição.
- Contraste conferido por script: `node docs/design/tokens/check-contrast.mjs`.

## Tipo

- Baloo 2 na marca, nos títulos, nas saudações e nas falas da Paçoca.
- Figtree na interface e nos números, com algarismos tabulares. Centavos menores nos valores em destaque.
- Fontes empacotadas no app, nunca baixadas em tempo de execução.

## Forma e movimento

- Cartões com 20 px de raio, chips com 12, botões em pílula. Espaçamento em múltiplos de 4. Pouca sombra.
- As três pintas da paca são o motivo gráfico: ícone, carregamento, R$ ••• e progresso.
- Ícones Phosphor: regular nas telas, duotone nas ilustrações.
- Microinterações de 150 a 250 ms e transições de 300 a 400 ms. Tudo respeita "reduzir movimento".

## Acessibilidade

- Texto com pelo menos 4,5:1 e componentes com pelo menos 3:1, nos dois temas.
- Cor nunca sozinha: categoria, essencialidade e alerta sempre têm nome, ícone ou rótulo.
- Cada gráfico tem resumo em texto, e o app aguenta texto a 200% e alvos de toque de 48 dp.
- Tema escuro de primeira classe: a paca é noturna.
