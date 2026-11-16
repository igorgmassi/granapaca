# Parte 2: Design tokens

Os tokens do GranaPaCá ficam em três arquivos na pasta [`tokens`](tokens/), e todos os pares de cor passam no contraste mínimo, nos dois temas.

- **Data:** 2026-11-10
- **Marcas:** [Suposição] e [Conferir: fonte], como na [Parte 1](01-revisao-das-decisoes.md).

| Arquivo | O que é |
|---|---|
| [`tokens.json`](tokens/tokens.json) | Fonte da verdade: cores, tipografia, espaço, raio, borda, sombra, tamanhos, layout e movimento. |
| [`granapaca_theme.dart`](tokens/granapaca_theme.dart) | Tema do Flutter: `ColorScheme` do Material 3, `ThemeData` e o `ThemeExtension` `GranaTokens`. |
| [`check-contrast.mjs`](tokens/check-contrast.mjs) | Confere 53 pares por tema a partir do JSON e sai com erro se algum falhar. |

```bash
node docs/design/tokens/check-contrast.mjs
```

## Cores da interface

Os tokens do briefing viram papéis do Material 3. Assim, os componentes padrão do Flutter já saem com as cores da marca.

| Token do briefing | Papel no Material 3 | Claro | Escuro |
|---|---|---|---|
| Caramelo | `primary` | #A0521A | #E8A066 |
| Sobre Caramelo | `onPrimary` | #FFFFFF | #2A1407 |
| Paçoca (fundo) | `surface` | #FBF5EC | #17110D |
| Superfície | `surfaceContainerLow` | #FFFFFF | #221A14 |
| Cacau | `onSurface` | #2A1C12 | #F7EFE6 |
| Cacau suave | `onSurfaceVariant` | #6B5546 | #C4B2A2 |
| Borda de campo | `outline` | #94816E | #86725F |
| Urucum | `error` | #B83A22 | #FF8B73 |
| Jabuticaba | `tertiary` | #6E4AA3 | #B9A0EE |

Mata, Milho, Sobre Milho, Rio e os três níveis de essencialidade não têm papel no Material 3. Eles ficam no `GranaTokens`, com os valores do briefing.

Três decisões novas:

- **`secondary` é um marrom quente** (#7A5A43 no claro, #DCC1A9 no escuro), não a Mata. A barra de navegação e os chips selecionados usam `secondaryContainer`, e verde neste app quer dizer receita.
- **Containers ajustados pelo script.** Na primeira versão, o Caramelo sobre o container mais alto ficava em 4,22:1. Os containers do claro ficaram mais claros e os do escuro, mais escuros, até os 106 pares passarem.
- **`outlineVariant`** é a borda suave dos cartões (#E5D9CA e #3F342A). É decorativa: o cartão se separa do fundo pela cor da Superfície.

## Cores dos gráficos

Cada grupo tem uma cor fixa, e a rosca segue sempre esta ordem, com Outros por último. A ordem alterna tons quentes e frios, para que duas cores parecidas nunca fiquem lado a lado.

| Ordem | Grupo | Cor | Claro | Escuro | Ícone (Phosphor) |
|---|---|---|---|---|---|
| 1 | Moradia | Caramelo | #8B3E05 | #9D4005 | `house` |
| 2 | Transporte | Rio | #277BD0 | #2B7DDA | `car` |
| 3 | Alimentação | Milho | #A78511 | #8D741C | `forkKnife` |
| 4 | Saúde | Mata | #267E4E | #31AD6D | `heartbeat` |
| 5 | Compras | Manga | #FE903C | #D67B16 | `shoppingBag` |
| 6 | Educação | Jabuticaba | #7F4B9D | #7A56B0 | `graduationCap` |
| 7 | Lazer | Goiaba | #D54573 | #CE436A | `popcorn` |
| 8 | Assinaturas e serviços | Igarapé | #02A8AA | #008E97 | `repeat` |
| 9 | Outros | Cinza quente | #A3958A | #8A7D73 | `dotsThree` |

Resultado do validador de cores (OKLab, simulação de daltonismo de Machado 2009):

| Tema | Pares | Visão normal (mín. 15) | Protanopia e deuteranopia (mín. 8) |
|---|---|---|---|
| Claro | Todos | 15,6 | 8,3 |
| Escuro | Vizinhos na rosca | 16,7 | 8,6 |
| Escuro | Todos | 12,7 | 6,5 |

Regras que saem desse resultado:

- **Rótulo obrigatório no tema escuro:** fora da ordem da rosca, algumas cores ficam parecidas. Toda fatia tem rótulo direto ou fica ao lado do ranking com nomes, e as fatias têm 2 px de separação.
- **Cores abaixo de 3:1 contra a Superfície** pedem rótulo visível: Manga, Igarapé e Outros no claro, e Caramelo no escuro.
- **A cor segue o grupo,** nunca a posição. Um filtro que tira grupos não repinta os que ficam.

O mapa de calor usa uma escala de Caramelo em 5 tons, do menor ao maior gasto. O dia sem gasto é uma célula vazia, só com a borda `outlineVariant`. A primeira versão da escala começava num tom que sumia contra o fundo; a atual passa no validador nos dois temas.

## Tipografia

| Estilo | Fonte | Tamanho / altura (px) | Peso | Uso |
|---|---|---|---|---|
| `displayMedium` | Baloo 2 | 40 / 48 | 600 | Título das etapas do primeiro acesso |
| `displaySmall` | Baloo 2 | 32 / 40 | 600 | Comemorações e estados vazios grandes |
| `headlineLarge` | Baloo 2 | 28 / 36 | 600 | Saudação do Início |
| `headlineMedium` | Baloo 2 | 24 / 32 | 600 | Título de tela |
| `headlineSmall` | Baloo 2 | 20 / 28 | 600 | Título de seção com a marca |
| `titleLarge` | Figtree | 20 / 28 | 600 | Título de folha e de diálogo |
| `titleMedium` | Figtree | 16 / 24 | 600 | Título de cartão, estabelecimento no extrato |
| `titleSmall` | Figtree | 14 / 20 | 600 | Subtítulo |
| `bodyLarge` | Figtree | 16 / 24 | 400 | Texto corrido |
| `bodyMedium` | Figtree | 14 / 20 | 400 | Texto padrão da interface |
| `bodySmall` | Figtree | 12 / 16 | 400 | Data, banco e legenda |
| `labelLarge` | Figtree | 14 / 20 | 600 | Botões e chips |
| `labelMedium` | Figtree | 12 / 16 | 600 | Barra de navegação |
| `labelSmall` | Figtree | 11 / 16 | 600 | Marcadores |
| `valorDestaque` | Figtree, tnum | 40 / 48, centavos 22 | 600 | "Sobrou este mês" |
| `valorGrande` | Figtree, tnum | 24 / 32, centavos 16 | 600 | Saldo e total da rosca |
| `valorLinha` | Figtree, tnum | 16 / 24 | 600 | Valor no extrato |
| `falaPacoca` | Baloo 2 | 18 / 26 | 500 | Falas da Paçoca |

Os quatro estilos de valor e a fala da Paçoca ficam no `GranaTokens`, porque o `TextTheme` não tem lugar para eles.

## Espaço, forma e sombra

| Grupo | Valores |
|---|---|
| Espaço | 4, 8, 12, 16, 24, 32 e 48. Margem lateral de 16 no celular, 24 no tablet e 32 no desktop. |
| Raio | Chip e campo 12, cartão 20, folha e diálogo 28, botão em pílula. |
| Borda | Cartão 1 px `outlineVariant`. Campo 1 px `outline`. Foco 2 px `primary`. |
| Sombra | Só em dois lugares: o botão "+" (0, 4, desfoque 12, Cacau a 16%) e a folha inferior (0, −2, desfoque 16, preto a 12%). |
| Tamanhos | Alvo de toque 48, ícone 24, círculo de categoria 40, avatar 40, faixa do banco 4, logo do banco 20, separação nos gráficos 2. |

## Layout

| Largura da janela | Navegação | Detalhe |
|---|---|---|
| Até 599 | Barra inferior | Em outra tela |
| 600 a 839 | Trilho lateral | Em outra tela |
| 840 ou mais | Trilho lateral | Ao lado da lista, em duas colunas |

O conteúdo para de crescer em 1200 px, para as linhas do extrato não ficarem longas demais.

## Movimento

| Token | Duração | Uso |
|---|---|---|
| `rapida` | 150 ms | Toque, troca de estado de chip |
| `micro` | 200 ms | Abrir menu, marcar item |
| `microLonga` | 250 ms | Expandir cartão |
| `transicao` | 300 ms | Trocar de tela |
| `transicaoLonga` | 400 ms | Etapa da trilha do primeiro acesso, folha inferior |
| `contagem` | 900 ms | Contagem do "Sobrou este mês" |
| `chuvaDeMoedas` | 1200 ms | Meta batida |

Curvas do Material 3: `padrao` (0,2; 0; 0; 1), `entrada` (0,05; 0,7; 0,1; 1) e `saida` (0,3; 0; 0,8; 0,15). Com "reduzir movimento", `GranaMovimento.ou` devolve duração zero: nada desliza, conta ou chove.

## Como usar no Flutter

```dart
MaterialApp(
  theme: granaTema(Brightness.light),
  darkTheme: granaTema(Brightness.dark),
);

// Num widget:
final grana = Theme.of(context).extension<GranaTokens>()!;
Text('+ R\$ 1.234,56', style: grana.valorLinha.copyWith(color: grana.mata));
```

## A conferir

- **O Dart não passou por análise.** O Flutter não está instalado na máquina onde os tokens foram escritos. Antes de usar, rode `flutter analyze` [Conferir: `CardThemeData` e `DialogThemeData` exigem Flutter 3.27 ou mais novo; `InputDecorationTheme` pode ter virado `InputDecorationThemeData` em versões recentes].
- **Fontes:** use os arquivos estáticos de cada peso (Baloo 2 500 e 600, Figtree 400 e 600) declarados no `pubspec.yaml`, com o `OFL.txt` ao lado. Fonte variável no Flutter não aplica o peso automaticamente em todas as plataformas [Conferir: docs.flutter.dev, fontes personalizadas].
- **Altura da Baloo 2:** a fonte tem métricas verticais altas: a 32 px, a linha natural dela mede 51 px, contra 39 px da Figtree. Use sempre a altura de linha do token e `TextLeadingDistribution.even`, para o texto não ficar baixo dentro de botões e títulos [Conferir: api.flutter.dev, TextStyle.leadingDistribution].
- **Logo e fontes:** o logo é serifado e não usa nenhuma das duas fontes. Ele entra sempre como imagem (SVG), nunca como texto digitado.
- **Ícones:** confira os nomes da tabela no pacote phosphor_flutter [Conferir: pub.dev/packages/phosphor_flutter].
