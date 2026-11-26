# Design do GranaPaCá

Resumo das decisões visuais que valem para todo o app (**identidade Toca Editorial**). O detalhe de cada parte está em [`docs/design`](docs/design/README.md), e os valores estão em [`docs/design/tokens/tokens.json`](docs/design/tokens/tokens.json).

## Mundo visual

- **Conceito:** a paca que junta tudo. O app é a toca da Paçoca, que traz a grana de todos os bancos (ou do cofre local no celular) pra cá.
- **Clima (Toca Editorial):** limpo, sereno e caloroso, com fundo algodão quente no modo claro (`#FAF8F5`) e toca noturna no escuro (`#14110F`), cartões com borda fina e terracota pontual longe do azul de banco.
- **Regra de ouro:** diversão nos detalhes, clareza no que importa. Navegação, números e botões são diretos e silenciosos. A graça mora na Paçoca, nas microanimações da criação de conta, nos estados vazios e nas comemorações.
- **Primeiro acesso:** superfícies limpas com a Paçoca apoiada diretamente sobre o cartão de cadastro, reagindo em tempo real à escolha do modo (*No celular*, *Meu servidor* ou *Demo*), à digitação do e-mail, à senha (tampando os olhos), à segurança (escudo/cadeado) e à conclusão, sem gamificação que cobra.

## Cor

- Paleta **Toca Editorial** sobre o Material 3: Terracota (`#A84C19` claro / `#E5965C` escuro) como marca (`primary`), Algodão/Toca Noturna como fundo (`surface`) e cartões nítidos (`#FFFFFF` / `#1E1A17`) com borda fina (`outlineVariant`).
- Gasto na cor do texto, com "−". Receita em Mata (`#1D6B48` / `#62C493`), com "+". Vermelho (Urucum) só para alerta e erro.
- Essencialidade é uma escala 100% em tons de Caramelo nos dois temas, sempre com o nome do nível ou as pintas (●●●, ●●○, ●○○).
- Gráficos usam 8 cores fixas por grupo, na ordem da rosca. A cor segue o grupo, nunca a posição.
- Contraste conferido por script (108 pares): `node docs/design/tokens/check-contrast.mjs`.

## Tipo

- `Plus Jakarta Sans` na marca, nos títulos, nas saudações e nas falas da Paçoca.
- `Inter` na interface e nos números, com algarismos tabulares (`tnum`). Centavos menores nos valores em destaque.
- Fontes empacotadas no app (OFL), nunca baixadas em tempo de execução.

## Logo, ícone e mascote

- **Logo (Opção B — Paca Deitada Evoluída):** wordmark geométrico limpo `Grana PaCá` (`Grana` em Cacau/Off-white e `PaCá` em Terracota/Âmbar) com a paca pintada sem contorno preto descansando sobre `PaCá`.
- **Ícone do app:** silhueta limpa da paca deitada com pintas creme sobre Terracota (claro), Âmbar sobre Obsidiana (escuro) e versão monocromática vazada para ícones temáticos.
- **Paçoca ilustrada refinada:** mantém o acabamento pintado suave sem contorno preto, **sem pochete**, com focinho suavemente alongado de paca brasileira e fileiras limpas de pintas creme.

## Forma e movimento

- Cartões com 20 px de raio e borda fina de 1 px, chips com 12, botões em pílula. Espaçamento em múltiplos de 4. Pouca sombra.
- As três pintas da paca são o motivo gráfico: carregamento, R$ •••, essencialidade e indicador de progresso.
- Ícones Phosphor: regular nas telas, duotone nas ilustrações.
- Microinterações de 150 a 250 ms, transições de 300 a 400 ms e coreografia dedicada da Paçoca na criação de conta (olhar acompanhando o texto, patas tampando os olhos na senha + espiadinha, escudo no 2FA/biometria e pulinho comemorativo). Tudo respeita "reduzir movimento".

## Acessibilidade

- Texto com pelo menos 4,5:1 e componentes com pelo menos 3:1, nos dois temas (108 pares conferidos).
- Cor nunca sozinha: categoria, essencialidade e alerta sempre têm nome, ícone ou rótulo.
- Cada gráfico tem resumo em texto, e o app aguenta texto a 200% e alvos de toque de 48 dp.
- Tema escuro de primeira classe: a paca é noturna.
