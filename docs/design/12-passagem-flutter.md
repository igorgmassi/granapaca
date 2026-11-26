# Parte 12: Passagem para o Flutter

O que o app precisa copiar, criar e conferir para sair das 11 partes de design e chegar ao `app/lib`. Esta é a última parte: depois dela, o trabalho é implementar.

- **Data:** 2026-11-26
- **Base do app hoje:** Flutter 3.50.0 e Dart 3.14.0, a versão do CI ([`app/README.md`](../../app/README.md)). O esqueleto traz um tema neutro, que o `main.dart` diz que será trocado pelos tokens do design.
- **Para conferir o tema:** `node docs/design/tokens/check-tema.mjs`
- **Marcas:** [Suposição] e [Conferir: fonte], como na [Parte 1](01-revisao-das-decisoes.md).
- **Dados:** fictícios, como em todo o repositório.

## Antes de começar: três avisos sobre o que já existe

1. **Identificadores em inglês.** O [`AGENTS.md`](../../AGENTS.md) manda código em inglês e texto de interface em português. O design usa nomes em português (`LinhaDeLancamento`, `GranaEspaco`) porque são os nomes das conversas e das folhas. No `app/lib`, o identificador vai em inglês e o texto que a pessoa lê continua em português. A tabela de equivalências está na seção de widgets. [Suposição: Igor confirma a tradução dos nomes na primeira PR do tema.]
2. **`material_ui`.** O app importa `package:material_ui/material_ui.dart` (a versão travada em `app/pubspec.lock` é a 1.11.0), e o [`granapaca_theme.dart`](tokens/granapaca_theme.dart) importa `package:flutter/material.dart`. Ao copiar o tema, troque o import para o mesmo do app [Conferir: pub.dev/packages/material_ui e se `FontFeature` segue em `dart:ui`].
3. **`taxonomy.dart` está desatualizado.** Itens de migração na seção [Migração do que existe](#migração-do-que-existe).

## Do `tokens.json` ao tema

O [`granapaca_theme.dart`](tokens/granapaca_theme.dart) já implementa quase tudo. O `check-tema.mjs` compara as cores dele com o JSON e hoje dá **100 valores conferidos, 0 diferenças**.

| Do `tokens.json` | No Dart | Observação |
|---|---|---|
| `cor.esquema.claro` e `escuro` | `ColorScheme` `_claro` e `_escuro` | Todas as chaves do esquema, conferidas pelo script |
| `cor.marca` (Mata, Milho, Sobre Milho, Rio, essencialidade) | `GranaTokens.mata`, `milho`, `sobreMilho`, `rio`, `essencial`, `importante`, `flexivel` | O escuro herda do claro o que não troca, com `copyWith` |
| `cor.grafico` (8 grupos na `ordemDaRosca`) | `GranaTokens.grafico` (lista) e `outros` | Ordem fixa. A cor segue o grupo, nunca a posição no ranking |
| `espaco` | `GranaEspaco` | Inclui `alvoDeToque`, que no JSON mora em `tamanho` |
| `raio` | `GranaRaio` e `StadiumBorder` | `pilula` vira `StadiumBorder`, não um número |
| `borda` | `cardTheme`, `inputDecorationTheme` | O foco de 2 px só existe no campo. Falta o anel de foco geral (abaixo) |
| `movimento.duracao` e `curva` | `GranaMovimento` | `GranaMovimento.ou` zera tudo com "reduzir movimento" |
| `tipografia.estilos` | `_textos` (`TextTheme`) e `GranaTokens.valor*`, `falaPacoca` | `tnum` por `FontFeature.tabularFigures()` |
| `layout` | `NavigationBar` e `NavigationRail` no tema | Os pontos de quebra ainda não são constantes |

**O que o JSON tem e o tema ainda não** (a saída do `check-tema.mjs` lista estes itens). Entram na primeira PR do tema:

| Falta | Para quê | Proposta |
|---|---|---|
| `pulsoCarregamento` (1000 ms) | Esqueleto e pintas de carregamento | Acrescentar em `GranaMovimento` |
| `cor.grafico.sequencial` (5 tons) | Mapa de calor | Lista nova em `GranaTokens`, uma por tema |
| `cor.categorias` (id, nome, cor, ícone) | Círculo e ícone de cada grupo | Mapa único de categoria para cor e ícone, junto da taxonomia |
| `tamanho` (círculo da categoria 40, avatar 40, faixa do banco 4, logo do banco 20, separação 2) | Lançamento, avatar do chat, gráficos | Constantes `GranaTamanho` |
| `sombra` (flutuante e folha) | Botão "+" e folha inferior | `BoxShadow` no `FloatingActionButtonThemeData` e `BottomSheetThemeData` |
| `layout` (599, 600 a 839, 840 em diante, 1200) | Barra, trilho e detalhe ao lado | `GranaLayout` e um `LayoutBuilder` na casca do app |
| Centavos menores (22 em `valorDestaque`, 16 em `valorGrande`) | "R$ 1.284,90" com centavos pequenos | O widget `ValorMonetario` recebe o tamanho dos centavos do token |
| Anel de foco (2 px `primary`, afastado 2) | Teclado no desktop | `focusColor` e um `FocusableActionDetector` nos componentes próprios |
| Ícone de categoria com tom próprio | Contraste de 3:1 no círculo | Depende da proposta da [Parte 11](11-acessibilidade.md) |

## Estrutura de pastas sugerida

O `app/lib` hoje tem `main.dart`, `demo/` e `finance/`. A sugestão mantém os dois e acrescenta o resto [Suposição].

```text
app/
  assets/
    fonts/               Plus Jakarta Sans e Inter (.ttf) com as licenças OFL ao lado
    pacoca/              quadros parados da Paçoca (fallback do Rive)
    rive/pacoca.riv      máquina de estados da Paçoca
    logo/                logo e símbolo em SVG, com o letreiro em <path>
  lib/
    main.dart
    theme/               granapaca_theme.dart (do design) e as constantes que faltam
    widgets/             componentes compartilhados (Partes 5 a 8)
    features/
      onboarding/        criação de conta e guia (Parte 6)
      home/              Início (Parte 6)
      statement/         Extrato e Detalhe do lançamento, com a folha de correção (Parte 7)
      spending/          Gastos: Análise e Planejamento (Partes 7 e 8)
      chat/              Pergunte pra Paçoca (Parte 8)
      receipts/          Comprovante, NFC-e e Dinheiro físico (Parte 8)
      alerts/            Alertas e alerta em linguagem natural (Parte 8)
      settings/          Configurações, modo demo e apagar tudo (Parte 8)
    pacoca/              PacocaAnimada, estados e fallback
    finance/             modelo e consultas (já existe)
    demo/                dados fictícios (já existe)
  test/
    goldens/             um golden por tela, claro e escuro
```

## Widgets principais

A coluna do meio é o nome usado no design. A da direita é o identificador sugerido no código, em inglês [Suposição]. A base é o Material 3 sempre que existir um widget equivalente, como na [Parte 5](05-componentes.md).

| Nome no design | Identificador no código | Base | Onde aparece |
|---|---|---|---|
| `GranaTokens`, `GranaEspaco`, `GranaRaio`, `GranaMovimento` | `GranaTokens`, `GranaSpacing`, `GranaRadius`, `GranaMotion` | `ThemeExtension` e constantes | Todo o app |
| `MarcadorDePintas` | `DotsMarker` | Próprio | Essencialidade, passos, carregamento |
| `LinhaDeLancamento` | `TransactionTile` | Próprio, sobre `ListTile` | Início, Extrato, Gastos |
| `FalaDaPacoca` | `PacocaSpeech` | `Card` | Início, Gastos, Chat |
| `FaixaDeAlerta` | `AlertStrip` | Próprio | Conexão vencendo, offline |
| `EstadoVazio` | `EmptyState` | Próprio | Toda lista sem dados |
| `PacocaAnimada` | `PacocaAnimated` | Rive e imagem parada | Onde a Paçoca aparece |
| `ValorMonetario` | `MoneyText` | `Text.rich` com `tnum` | Todo valor. Recebe `int` em centavos ([ADR-013](../adr/0013-dinheiro-em-centavos.md)) e lê o modo "valor oculto" |
| `NavegacaoAdaptativa` | `AdaptiveShell` | `NavigationBar` e `NavigationRail` | Casca do app |
| `GraficoRosca` | `SpendingDonut` | `fl_chart` (`PieChart`) | Gastos, Início no desktop |
| `RankingDeCategorias` | `CategoryRanking` | Lista de barras | Gastos |
| `BarrasDeEvolucao` | `MonthlyBars` | `fl_chart` (`BarChart`) | Gastos |
| `MapaDeCalor` | `SpendingHeatmap` | Próprio, grade de células com `Semantics` | Gastos |
| `BarraCincoTrintaVinte` | `FiftyThirtyTwentyBar` | Próprio | Gastos |
| `FolhaDeCorrecao` | `CorrectionSheet` | `showModalBottomSheet` | Detalhe e Extrato |
| `LinhaDoTempoDeAjustes` | `AdjustmentTimeline` | Próprio | Detalhe da transação |
| `BolhaDeChat` | `ChatBubble` | Próprio | Chat |
| `CartaoDeResposta` | `AnswerCard` | `Card` | Chat |
| `AvisoDeMinimizacao` | `MinimizationNotice` | Próprio | Chat e provedores de IA |
| `TecladoNumerico` | `AmountKeypad` | Próprio | Dinheiro físico |
| `ItemDeComprovante` | `ReceiptItemTile` | Próprio | NFC-e e divisão do valor |
| `BannerModoDemo` | `DemoBanner` | Próprio, fixo no topo | Toda tela no modo demo |
| `FaixaDeBanco` | `BankStripe` | `Container` de 4 de largura | Lançamento e conta conectada |

Regras para todos:

- **Valor sempre pelo `MoneyText`.** Nenhuma tela formata dinheiro por conta própria. Ele cuida do formato `R$ 1.234,56`, do sinal `-` nas saídas, do modo oculto (`R$ •••`, lido como "valor oculto") e dos centavos menores [Conferir: pub.dev/packages/intl, `NumberFormat.currency` com `pt_BR`].
- **Cor vem do tema.** Nenhum `Color(0x...)` fora de `theme/`. O `flutter analyze --fatal-infos` não pega isso sozinho; vale uma regra de revisão [Suposição].
- **Alvo de 48.** Componente próprio interativo envolve o desenho em `ConstrainedBox` com `GranaSpacing.touchTarget` ([Parte 11](11-acessibilidade.md)).
- **Texto de interface em português, no código em arquivo de textos único** (por exemplo `lib/l10n/`), para a revisão de microcopy da [Parte 10](10-microcopy.md) mexer num lugar só [Suposição].

## Pacotes

Todos os nomes e versões são para conferir na hora de adicionar. Cada `pubspec.yaml` novo exige o `pubspec.lock` junto, porque o CI roda `flutter pub get --enforce-lockfile`.

| Pacote | Para quê | Observação |
|---|---|---|
| Fontes empacotadas, sem pacote | `Plus Jakarta Sans` e `Inter` | O tema já usa `fontFamily: 'Inter'` pelo nome. Basta declarar `fonts:` no `pubspec.yaml`. O app nunca baixa fonte ao abrir ([Parte 1](01-revisao-das-decisoes.md), mudança 11) |
| `google_fonts` | Alternativa às fontes declaradas | Se usado, com `GoogleFonts.config.allowRuntimeFetching = false` e os arquivos em `assets/google_fonts/` [Conferir: pub.dev/packages/google_fonts] |
| `phosphor_flutter` | Ícones regular e duotone | [Conferir: pub.dev/packages/phosphor_flutter] |
| `rive` | A Paçoca animada | [Conferir: pub.dev/packages/rive, a API de máquina de estados e de entradas na versão usada] |
| `fl_chart` | Rosca e barras | `sectionsSpace` de 2 para a separação, `centerSpaceRadius` para o furo, toque por fatia [Conferir: pub.dev/packages/fl_chart] |
| `flutter_svg` | Logo e quadros parados em SVG | [Conferir: pub.dev/packages/flutter_svg] |
| `intl` | Formato de dinheiro e data em `pt_BR` | [Conferir: pub.dev/packages/intl] |

- **Fora da lista:** `flutter_heatmap_calendar` saiu na [Parte 1](01-revisao-das-decisoes.md), mudança 16. O mapa de calor é widget próprio, para ter rótulo por dia, modo oculto e tokens da marca.
- **Licença:** conferir a licença de cada pacote contra a AGPL-3.0 do projeto antes de adicionar [Conferir: licença de cada pacote].

Declaração das fontes, com os pesos que os estilos do `tokens.json` usam (`Plus Jakarta Sans` em 500, 600 e 700; `Inter` em 400, 600 e 700):

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: Plus Jakarta Sans
      fonts:
        - { asset: assets/fonts/PlusJakartaSans-Medium.ttf, weight: 500 }
        - { asset: assets/fonts/PlusJakartaSans-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/PlusJakartaSans-Bold.ttf, weight: 700 }
    - family: Inter
      fonts:
        - { asset: assets/fonts/Inter-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/Inter-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/Inter-Bold.ttf, weight: 700 }
```

Os nomes dos arquivos dependem de onde as fontes forem baixadas. A `Inter` precisa ter o recurso `tnum`, que o Google Fonts oferece [Conferir: que a build empacotada mantém o recurso `tnum`, com um golden de valores alinhados].

## A Paçoca no app

### Máquina de estados no Rive

O arquivo `pacoca.riv` e as entradas estão especificados na [Parte 3](03-mascote.md) e não mudam aqui. O que o app precisa:

| Entrada | Tipo | Quem mexe |
|---|---|---|
| `estado` | Número, 0 a 9 | A tela, pela expressão que a situação pede |
| `profundidade` | Número, 0 a 100 | O gesto de puxar para atualizar |
| `etapaCadastro` | Número, 0 a 5 | A criação de conta |
| `direcaoOlhar` | Número, −1 a 1 | Cartões de modo de acesso |
| `progressoTexto` | Número, 0 a 1 | Campo de nome ou e-mail |
| `cobrirOlhos`, `espiadinha` | Booleano | Campo de senha e o olho de mostrar |
| `progressoSeguranca` | Número, 0 a 3 | Código de 6 dígitos |
| `erroCalmo`, `comemorar` | Gatilho | Erro de código, meta batida e conta pronta |

Qual `estado` cada situação usa:

| Situação | Expressão | `estado` |
|---|---|---|
| Boas-vindas, guia | Acenando | 1 |
| Meta batida, mês com sobra | Comemorando | 2 |
| IA pensando, chat digitando | Pensando | 3 |
| Lendo nota fiscal | Com lupa | 4 |
| Sem internet, sincronização pendente | Dormindo | 5 |
| Puxar para atualizar | Mergulhando | 6 |
| Alerta, conexão vencendo | Preocupada, sem drama | 7 |
| Privacidade e segurança | Segurando um cadeado | 8 |
| Guia e transições | Andando | 9 |

### Widget com fallback parado

A Paçoca animada não pode ser requisito para a tela funcionar. Esboço do widget, que não depende da API do `rive` (essa parte é [Conferir]):

```dart
class PacocaAnimated extends StatelessWidget {
  const PacocaAnimated({super.key, required this.expression, this.height = 120, this.semanticLabel});

  final PacocaExpression expression;
  final double height;

  /// Só quando a Paçoca é o único sinal da tela. Com a frase ao lado dizendo o estado, fica nulo e ela é decorativa.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context) || (kIsWeb && !riveReady);
    final art = still ? PacocaStill(expression, height: height) : PacocaRive(expression, height: height);
    return semanticLabel == null ? ExcludeSemantics(child: art) : Semantics(label: semanticLabel, image: true, child: art);
  }
}
```

- **Quando usa o quadro parado:** "reduzir movimento" ligado (`MediaQuery.disableAnimationsOf`), testes de golden e a demo web enquanto o Rive carrega ([Parte 3](03-mascote.md), seção "Máquina de estados no Rive"). A troca é um fade de 150 ms (`GranaMotion.fast`, `GranaMovimento.rapida` no design).
- **Quadros parados:** as poses aprovadas em [`mascote/ilustrada`](mascote/ilustrada) cobrem acenando, comemorando, pensando, lupa, dormindo, preocupada e cadeado. **Faltam mergulhando e andando** em PNG recortado. Até alguém desenhar, o fallback delas usa os SVGs de [`mascote/`](mascote/) [Suposição]. Se a diferença de estilo incomodar, pedir as duas poses em issue, como manda o [README](README.md).
- **Onde ela não entra:** em lista de transações e ao lado de valor negativo em tom de piada ([Parte 3](03-mascote.md)). Uma vez por tela, no máximo. Um `PacocaAnimated` por tela é uma regra de revisão.
- **Tamanhos:** avatar do chat com 40 e só a cabeça; puxar para atualizar com 48; fala com 64; estado vazio com 120; primeiro acesso de 160 a 240. Abaixo de 48, só a cabeça.
- **Golden:** cada expressão tem um teste com a Paçoca parada, nos dois temas.

## Letreiro em `<path>`

Hoje o letreiro `Grana PaCá` dos SVGs de [`logo`](logo/) é um `<text>` com `Plus Jakarta Sans Bold`, `font-size` 82, `letter-spacing` de −2,4 e `textLength` de 480 ([Parte 4](04-logo-e-icone.md)). Isso depende da fonte instalada em quem abre o arquivo. Para impressão, loja de aplicativos e qualquer visualizador, o texto precisa virar contorno.

[`letreiro.json`](logo/letreiro.json) **não serve para isso**: são os contornos do logo serifado de 2026-11-12, anterior à Toca Editorial.

O script [`vetorizar-letreiro.mjs`](logo/vetorizar-letreiro.mjs) faz a troca sem mexer nos SVGs existentes:

```bash
# uma vez, fora do Git (o node_modules do design está no .gitignore)
npm install --no-save --prefix docs/design opentype.js @fontsource/plus-jakarta-sans

node docs/design/logo/vetorizar-letreiro.mjs \
  --fonte docs/design/node_modules/@fontsource/plus-jakarta-sans/files/plus-jakarta-sans-latin-700-normal.woff \
  --entrada docs/design/logo/logo-cor.svg \
  --saida docs/design/logo/logo-cor-vetor.svg
```

Como funciona:

1. Lê o `<text>` e os dois `<tspan>` do SVG de entrada (posição, tamanho, `letter-spacing`, `textLength` e a cor de "Grana" e de "PaCá").
2. Monta cada letra com o avanço do glifo, o *kerning* da fonte e o espaçamento. A diferença até o `textLength` de 480 é repartida entre as letras, como o navegador faz com `lengthAdjust="spacing"`.
3. Troca o `<text>` por dois `<path>`, um por palavra, nas mesmas cores, dentro de `<g aria-hidden="true">`. A paca e o `<title>` do SVG ficam como estavam, e o texto acessível continua sendo o `<title>`.
4. A `--saida` nunca pode ser a `--entrada`.

Resultado conferido em 2026-11-26 com o `logo-cor.svg`: nenhum `<text>` restante, nenhum `NaN` ou `undefined`, pontos de contorno de "Grana" entre x 22,1 e 259,4 e de "PaCá" entre 287,6 e 489,3, dentro da faixa de 18 a 498 do `textLength` original. Falta olhar o resultado renderizado ao lado do original antes de trocar os logos [Conferir: em visualizador de SVG].

- **Por que glifo a glifo:** o layout de texto do `opentype.js` falhou com esta fonte (`substitutionType 62, lookupType 6, substFormat 2 is not yet supported`). Para o alfabeto latino do letreiro, o avanço e o *kerning* bastam [Conferir: opentype.js, se versões novas suportam o lookup].
- **Fonte:** o arquivo `.woff` acima é o subconjunto latino da `Plus Jakarta Sans` Bold (licença OFL) do pacote `@fontsource`. Quando os `.ttf` entrarem em `assets/fonts/`, basta apontar `--fonte` para eles, com a licença OFL ao lado [Conferir: arquivo de licença que acompanha a fonte baixada].
- **O que ainda falta decidir:** quais arquivos vetorizados entram no repositório (`logo-cor`, `logo-escuro` e `logo-mono`) e se o `gerar-logo.mjs` passa a chamar este script. Hoje o `gerar-logo.mjs` continua gerando o `<text>`, e trocar isso muda a [Parte 4](04-logo-e-icone.md) [Suposição: tratar em PR própria].

## Migração do que existe

| Onde | Hoje | Como deve ficar |
|---|---|---|
| `app/lib/main.dart` | `ColorScheme.fromSeed(seedColor: Colors.blueGrey)` | `theme: granaTema(Brightness.light)` e `darkTheme: granaTema(Brightness.dark)` (nomes do arquivo de referência, antes da tradução) |
| `app/lib/finance/taxonomy.dart`, `Essentiality` | `superfluous('Supérfluo')` | `flexible('Flexível')`, como na [Parte 1](01-revisao-das-decisoes.md) (o tom de voz proíbe "Supérfluo") |
| `app/lib/finance/taxonomy.dart`, níveis | Três níveis sem escala de pintas | `essential`, `important` e `flexible`, cada um com 3, 2 e 1 pinta |
| `app/lib/finance/taxonomy.dart`, `SpendingCategory` | Ordem: moradia, alimentação, transporte, saúde, educação, lazer, compras, serviços, outros | Ordem fixa da rosca: moradia, transporte, alimentação, saúde, compras, educação, lazer, assinaturas e serviços, outros |
| `app/lib/finance/taxonomy.dart`, rótulo | `Serviços e assinaturas` | `Assinaturas e serviços`, como nos tokens |
| `app/lib/finance/taxonomy.dart`, `donutCategories` | 5 | Mantém 5, que é a regra da [Parte 1](01-revisao-das-decisoes.md), mudança 9 |
| `app/lib/demo/demo_data.dart` e testes | Usam os nomes antigos | Atualizar junto, com os dados fictícios das Partes 6 a 8 (Bia, Banco Ipê e Banco Jatobá) |

## Checklist de telas

Cada tela entra com widget test, golden nos dois temas e o `Semantics` da [Parte 11](11-acessibilidade.md). As folhas de referência ficam em [`telas`](telas/) e terminam em `-claro.svg` ou `-escuro.svg`.

| Tela | Folha de referência | Parte | Feature | Pronta |
|---|---|---|---|---|
| Criação de conta, etapas 1 a 5 | `trilha-1` | [6](06-telas-a.md) | `onboarding` | ☐ |
| Guia de perfil, etapas 6 a 10 | `trilha-2` | [6](06-telas-a.md) | `onboarding` | ☐ |
| Início, celular e desktop | `inicio`, `inicio-desktop` | [6](06-telas-a.md) | `home` | ☐ |
| Extrato, celular e desktop | `extrato`, `extrato-desktop` | [7](07-telas-b.md) | `statement` | ☐ |
| Detalhe da transação e correção | `detalhe` | [7](07-telas-b.md) | `statement` | ☐ |
| Gastos: Análise, celular e desktop | `gastos`, `gastos-desktop` | [7](07-telas-b.md) | `spending` | ☐ |
| Chat "Pergunte pra Paçoca" | `chat` | [8](08-telas-c.md) | `chat` | ☐ |
| Comprovante, NFC-e e Dinheiro físico | `comprovantes` | [8](08-telas-c.md) | `receipts` | ☐ |
| Planejamento e Alertas | `planejamento` | [8](08-telas-c.md) | `spending`, `alerts` | ☐ |
| Configurações e modo demo | `config` | [8](08-telas-c.md) | `settings` | ☐ |

Ordem sugerida de implementação [Suposição]: tema e fontes; `MoneyText`, `DotsMarker`, `TransactionTile`; casca de navegação; Início; Extrato e Detalhe; Gastos; comprovantes e dinheiro físico; Chat; Planejamento e Alertas; Configurações; Paçoca animada por último, porque o fallback parado cobre tudo antes dela.

## Antes de abrir cada PR do app

Do [`AGENTS.md`](../../AGENTS.md), dentro de `app/`:

```bash
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
```

E, na raiz do repositório, quando a PR tocar nos tokens ou no tema de referência:

```bash
node docs/design/tokens/check-contrast.mjs
node docs/design/tokens/check-categorias.mjs
node docs/design/tokens/check-daltonismo.mjs
node docs/design/tokens/check-tema.mjs
```

- **Golden:** o tema claro e o escuro de cada tela, com texto a 100% e a 200%, e com os valores visíveis e ocultos [Conferir: `flutter test --update-goldens` roda igual no CI e no computador de quem desenha, por causa da renderização de fonte].
- **Semântica:** teste de widget para a frase do lançamento, "valor oculto" e o resumo da rosca.
- **Mudou uma cor?** Edite o `tokens.json`, rode `check-contrast.mjs` e `check-tema.mjs`, e só então o `granapaca_theme.dart`.

## Próximo

O design está completo: as 12 partes estão prontas, e o que sobrou de decisão está marcado com [Suposição] e [Conferir]. O próximo passo é implementar o `app/` (Fase 1), começando pelo tema e pelos componentes compartilhados.
