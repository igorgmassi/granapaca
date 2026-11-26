# Parte 2: Design tokens

Os tokens do GranaPaCá (**identidade Toca Editorial**) ficam em três arquivos na pasta [`tokens`](tokens/), e todos os 108 pares de cor passam no contraste mínimo, nos dois temas.

- **Data:** 2026-11-10; refinados para Toca Editorial em 2026-11-24
- **Marcas:** [Suposição] e [Conferir: fonte], como na [Parte 1](01-revisao-das-decisoes.md).

| Arquivo | O que é |
|---|---|
| [`tokens.json`](tokens/tokens.json) | Fonte da verdade: cores, tipografia, espaço, raio, borda, sombra, tamanhos, layout e movimento. |
| [`granapaca_theme.dart`](tokens/granapaca_theme.dart) | Tema do Flutter: `ColorScheme` do Material 3, `ThemeData` e o `ThemeExtension` `GranaTokens`. |
| [`check-contrast.mjs`](tokens/check-contrast.mjs) | Confere 54 pares por tema (108 no total) a partir do JSON e sai com erro se algum falhar. |

```bash
node docs/design/tokens/check-contrast.mjs
```

## Cores da interface

Os tokens viram papéis do Material 3 para manter superfícies arejadas, hierarquia silenciosa e leitura nítida em claro e escuro.

| Token | Papel no Material 3 | Claro (`Toca Editorial`) | Escuro (`Toca Noturna`) |
|---|---|---|---|
| Terracota / Âmbar | `primary` | `#A84C19` | `#E5965C` |
| Sobre Terracota | `onPrimary` | `#FFFFFF` | `#211106` |
| Algodão / Toca (fundo) | `surface` | `#FAF8F5` | `#14110F` |
| Superfície (cartão) | `surfaceContainerLow` | `#FFFFFF` | `#1E1A17` |
| Cacau (texto) | `onSurface` | `#231C16` | `#F5F1EC` |
| Cacau suave | `onSurfaceVariant` | `#63564B` | `#B5A89C` |
| Borda de campo | `outline` | `#8A7B6D` | `#8A7A6C` |
| Borda fina de cartão | `outlineVariant` | `#E8E2DA` | `#2E2823` |
| Urucum (erro/alerta) | `error` | `#B53720` | `#FF8B73` |
| Jabuticaba (chat/IA) | `tertiary` | `#6B489E` | `#B9A0EE` |

Mata (`#1D6B48` claro / `#62C493` escuro), Milho, Sobre Milho, Rio e os três níveis de essencialidade ficam em `GranaTokens`.

- **`secondary` é um marrom neutro quente** (`#6F5A4A` claro, `#D6C3B3` escuro), mantendo o verde Mata exclusivo para receitas e sinais positivos.
- **Essencialidade 100% em escala de Caramelo nos dois temas:** `#6F340E / #A65E28 / #BC7638` no claro e `#F5CBA4 / #DA955C / #B5733C` no escuro — nunca misturar verde ou vermelho na barra de essencialidade.
- **Containers calibrados pelo script:** todos os 54 pares do claro e 54 pares do escuro passam com margem em WCAG AA (textos ≥ 4,5:1 e bordas/componentes ≥ 3:1).

## Cores dos gráficos

Cada grupo tem uma cor fixa, e a rosca segue sempre esta ordem, com Outros por último. A ordem alterna tons quentes e frios, para que duas cores parecidas nunca fiquem lado a lado.

| Ordem | Grupo | Cor | Claro | Escuro | Ícone (Phosphor) |
|---|---|---|---|---|---|
| 1 | Moradia | Caramelo | `#8B3E05` | `#9D4005` | `house` |
| 2 | Transporte | Rio | `#277BD0` | `#2B7DDA` | `car` |
| 3 | Alimentação | Milho | `#A78511` | `#8D741C` | `forkKnife` |
| 4 | Saúde | Mata | `#267E4E` | `#31AD6D` | `heartbeat` |
| 5 | Compras | Manga | `#FE903C` | `#D67B16` | `shoppingBag` |
| 6 | Educação | Jabuticaba | `#7F4B9D` | `#7A56B0` | `graduationCap` |
| 7 | Lazer | Goiaba | `#D54573` | `#CE436A` | `popcorn` |
| 8 | Assinaturas e serviços | Igarapé | `#02A8AA` | `#008E97` | `repeat` |
| 9 | Outros | Cinza quente | `#A3958A` | `#8A7D73` | `dotsThree` |

- **Rótulo obrigatório:** cores abaixo de 3:1 contra a Superfície (Manga, Igarapé e Outros no claro; Caramelo no escuro) aparecem sempre com rótulo visível ou ranking ao lado e 2 px de separação entre fatias.
- **Mapa de calor:** escala sequencial de Caramelo em 5 tons, do menor ao maior gasto; dia sem gasto fica como célula vazia com borda `outlineVariant`.

## Tipografia

`Plus Jakarta Sans` na marca, títulos e falas da Paçoca; `Inter` com algarismos tabulares (`tnum`) na interface e nos valores numéricos.

| Estilo | Fonte | Tamanho / altura (px) | Peso | Uso |
|---|---|---|---|---|
| `displayMedium` | Plus Jakarta Sans | 36 / 44 | 700 | Título principal do primeiro acesso |
| `displaySmall` | Plus Jakarta Sans | 30 / 38 | 700 | Comemorações e estados vazios grandes |
| `headlineLarge` | Plus Jakarta Sans | 26 / 34 | 700 | Saudação do Início |
| `headlineMedium` | Plus Jakarta Sans | 22 / 30 | 700 | Título de tela e etapas do cadastro |
| `headlineSmall` | Plus Jakarta Sans | 18 / 26 | 600 | Título de seção |
| `titleLarge` | Inter | 20 / 28 | 600 | Título de folha e diálogo |
| `titleMedium` | Inter | 16 / 24 | 600 | Título de cartão e estabelecimento |
| `titleSmall` | Inter | 14 / 20 | 600 | Subtítulo |
| `bodyLarge` | Inter | 16 / 24 | 400 | Texto corrido |
| `bodyMedium` | Inter | 14 / 20 | 400 | Texto padrão da interface |
| `bodySmall` | Inter | 12 / 16 | 400 | Data, banco e legenda |
| `labelLarge` | Inter | 14 / 20 | 600 | Botões e chips |
| `labelMedium` | Inter | 12 / 16 | 600 | Barra de navegação |
| `labelSmall` | Inter | 11 / 16 | 600 | Marcadores |
| `valorDestaque` | Inter, `tnum` | 38 / 46, centavos 22 | 700 | "Sobrou este mês" |
| `valorGrande` | Inter, `tnum` | 24 / 32, centavos 16 | 600 | Saldo e total da rosca |
| `valorLinha` | Inter, `tnum` | 16 / 24 | 600 | Valor no extrato |
| `falaPacoca` | Plus Jakarta Sans | 16 / 24 | 500 | Falas da Paçoca |

## Espaço, forma e sombra

| Grupo | Valores |
|---|---|
| Espaço | 4, 8, 12, 16, 24, 32 e 48. Margem lateral de 16 no celular, 24 no tablet e 32 no desktop. |
| Raio | Chip e campo 12, cartão 20, folha e diálogo 28, botão em pílula. |
| Borda | Cartão 1 px `outlineVariant`. Campo 1 px `outline`. Foco 2 px `primary`. |
| Sombra | Apenas no botão "+" (0, 4, desfoque 12, Cacau a 14%) e na folha inferior (0, −2, desfoque 16, preto a 10%). |
| Tamanhos | Alvo de toque 48, ícone 24, círculo de categoria 40, avatar 40, faixa do banco 4, logo do banco 20, separação nos gráficos 2. |

## Movimento

| Token | Duração | Uso |
|---|---|---|
| `rapida` | 150 ms | Toque, troca de estado de chip e fade em "reduzir movimento" |
| `micro` | 200 ms | Abrir menu, marcar item |
| `microLonga` | 250 ms | Expandir cartão, trocar expressão da Paçoca |
| `transicao` | 300 ms | Trocar de tela |
| `transicaoLonga` | 400 ms | Transição de etapa e folha inferior |
| `olharTexto` | 120 ms | Acompanhamento do olhar da Paçoca ao digitar e-mail/nome |
| `cobrirOlhos` | 220 ms | Patas subindo para cobrir os olhos no campo de senha |
| `espiadinha` | 180 ms | Afastar uma pata ao tocar em "mostrar senha" |
| `erroCalmo` | 320 ms | Balanço sereno de cabeça em erro de código/credencial |
| `pulinhoConclusao` | 520 ms | Pulinho comemorativo com 3 pintas-moedinhas ao concluir a conta |
| `contagem` | 900 ms | Contagem do "Sobrou este mês" |
| `chuvaDeMoedas` | 1200 ms | Meta batida |

Com "reduzir movimento" ligado (`MediaQuery.disableAnimationsOf(context)`), `GranaMovimento.ou` devolve `Duration.zero`: sem deslizes, pulos ou chuva de moedas.
