# Parte 11: Checagem de acessibilidade

O que já foi medido por script, o que o desenho garante sem depender de cor, e o que ainda precisa de aparelho de verdade. Os números desta página saem dos três scripts da pasta [`tokens`](tokens/), e nenhum foi medido no olho.

- **Data:** 2026-11-26
- **Para conferir:** `node docs/design/tokens/check-contrast.mjs`, `node docs/design/tokens/check-categorias.mjs` e `node docs/design/tokens/check-daltonismo.mjs`. O quarto script da pasta, `check-tema.mjs`, compara o tema Dart com o JSON ([Parte 12](12-passagem-flutter.md))
- **Referência:** WCAG 2.2, nível AA [Conferir: w3.org/TR/WCAG22]. Texto com 4,5:1 e componentes com 3:1, nos dois temas.
- **Marcas:** [Suposição] e [Conferir: fonte], como na [Parte 1](01-revisao-das-decisoes.md).
- **Dados:** fictícios, como em todo o repositório.

## Resumo

| Item | Como foi conferido | Resultado |
|---|---|---|
| Contraste dos pares de cor | `check-contrast.mjs`, 54 pares por tema (108 no total) | Todos passam |
| Ícone dentro do círculo da categoria | `check-categorias.mjs` | **5 de 18 ficam abaixo de 3:1** (proposta na seção própria) |
| Distinção entre cores sem ver cor | `check-daltonismo.mjs` | Passa no claro. No escuro, a distância cai e a rosca depende de rótulo e ordem |
| Cor como único sinal | Revisão do desenho das Partes 5 a 8 | Nenhum caso: toda cor tem nome, ícone, sinal ou pintas junto |
| Texto até 200%, alvos de 48, foco, `Semantics` | Regras e checklist abaixo | Definido no desenho, **a medir no app** |
| TalkBack, VoiceOver, teclado no desktop | Nada disso roda ainda | **Pendente**, lista no fim da página |

## Contraste

Saída real do `check-contrast.mjs`:

```text
claro: 54 pares conferidos; gráfico com rótulo obrigatório: manga 2.27:1, igarape 2.92:1, outros 2.91:1
escuro: 54 pares conferidos; gráfico com rótulo obrigatório: caramelo 2.61:1
Todos os pares passam.
```

O script sai com código 1 se qualquer par ficar abaixo do mínimo, então serve de trava. Hoje nenhum workflow do CI roda os scripts de design [Suposição: ligar o `check-contrast.mjs` e o `check-tema.mjs` num workflow próprio]. Os pares que mais pesam no dia a dia, com a razão medida:

| Par | Claro | Escuro | Mínimo |
|---|---|---|---|
| Texto (`onSurface`) sobre o fundo (`surface`) | 15,86:1 | 16,72:1 | 4,5 |
| Texto sobre o cartão (`surfaceContainerLow`) | 16,81:1 | 15,37:1 | 4,5 |
| Texto secundário (`onSurfaceVariant`) sobre o fundo | 6,69:1 | 8,10:1 | 4,5 |
| Texto secundário sobre o cartão | 7,09:1 | 7,44:1 | 4,5 |
| Rótulo do botão (`onPrimary`) sobre `primary` | 5,66:1 | 7,71:1 | 4,5 |
| Link e ação (`primary`) sobre o cartão | 5,66:1 | 7,28:1 | 4,5 |
| Erro (`error`) sobre o cartão | 5,95:1 | 7,56:1 | 4,5 |
| Receita (`mata`) sobre o cartão | 6,46:1 | 8,09:1 | 4,5 |
| Informação (`rio`) sobre o cartão | 6,23:1 | 8,23:1 | 4,5 |
| Chat e IA (`tertiary`) sobre o cartão | 6,89:1 | 7,67:1 | 4,5 |
| Borda de campo (`outline`) sobre o fundo | 3,86:1 | 4,55:1 | 3 |
| Borda de campo sobre o cartão | 4,09:1 | 4,18:1 | 3 |
| Texto sobre Milho (`sobreMilho`) | 7,86:1 | 10,22:1 | 4,5 |
| Essencial sobre o cartão | 9,66:1 | 11,49:1 | 3 |
| Importante sobre o cartão | 4,94:1 | 6,94:1 | 3 |
| Flexível sobre o cartão | 3,63:1 | 4,51:1 | 3 |
| Flexível sobre o fundo (pior caso) | 3,42:1 | 4,91:1 | 3 |

- **Milho** só funciona como fundo, com texto Cacau por cima. Como ícone ou borda sobre branco, ele fica em 2,14:1 e **não entra** em nenhum desses usos.
- **Cores de gráfico abaixo de 3:1** (Manga, Igarapé e Outros no claro; Caramelo no escuro) pedem rótulo visível, ranking ao lado e 2 px de separação entre fatias. As telas das Partes [7](07-telas-b.md) e [8](08-telas-c.md) devem seguir isso, e a revisão de cada tela confere.
- **Mapa de calor:** os dois primeiros tons da escala sequencial ficam em 2,08:1 e 2,78:1 sobre o cartão no claro (2,33:1 no primeiro do escuro). Por isso o dia nunca é só a cor: cada célula tem rótulo de acessibilidade e abre os lançamentos do dia ao tocar. Dia sem gasto é célula vazia com borda `outlineVariant`.
- **Foco:** o anel de 2 px em `primary` tem 5,34:1 sobre o fundo e 5,66:1 sobre o cartão no claro, e 7,92:1 e 7,28:1 no escuro. Sobre a pílula `secondaryContainer`, 4,75:1 e 5,34:1.

### Ícones de categoria no círculo

A [Parte 5](05-componentes.md) deixou uma pergunta em aberto: a cor de gráfico de algumas categorias perde contraste dentro do círculo de 14% da própria cor. O `check-categorias.mjs` mede o ícone (a cor cheia do grupo) contra o círculo (a mesma cor a 14% sobre o cartão), com mínimo de 3:1:

```text
claro (círculo = cor a 14% sobre #FFFFFF, mínimo 3:1 para ícone)
categoria               cor      círculo  no círculo  na superfície  situação
Moradia                 #8B3E05  #EFE4DC  6.02:1      7.53:1         ok
Transporte              #277BD0  #E1EDF8  3.66:1      4.35:1         ok
Alimentação             #A78511  #F3EEDE  3.01:1      3.50:1         ok
Saúde                   #267E4E  #E1EDE6  4.18:1      5.03:1         ok
Compras                 #FE903C  #FFEFE4  2.02:1      2.27:1         abaixo; ícone sugerido #C77333 (3.16:1)
Educação                #7F4B9D  #EDE6F1  5.06:1      6.18:1         ok
Lazer                   #D54573  #F9E5EB  3.54:1      4.26:1         ok
Assinaturas e serviços  #02A8AA  #DCF3F3  2.53:1      2.92:1         abaixo; ícone sugerido #079394 (3.24:1)
Outros                  #A3958A  #F2F0EF  2.56:1      2.91:1         abaixo; ícone sugerido #908379 (3.24:1)

escuro (círculo = cor a 14% sobre #1E1A17, mínimo 3:1 para ícone)
categoria               cor      círculo  no círculo  na superfície  situação
Moradia                 #9D4005  #301F14  2.38:1      2.61:1         abaixo; ícone sugerido #AA5B28 (3.18:1)
Transporte              #2B7DDA  #202832  3.58:1      4.15:1         ok
Alimentação             #8D741C  #2E2718  3.27:1      3.82:1         ok
Saúde                   #31AD6D  #212F23  4.90:1      6.03:1         ok
Compras                 #D67B16  #382817  4.52:1      5.52:1         ok
Educação                #7A56B0  #2B222C  2.77:1      3.11:1         abaixo; ícone sugerido #805EB3 (3.05:1)
Lazer                   #CE436A  #372023  3.33:1      3.81:1         ok
Assinaturas e serviços  #008E97  #1A2A29  3.78:1      4.37:1         ok
Outros                  #8A7D73  #2D2824  3.65:1      4.33:1         ok

5 ícone(s) abaixo de 3:1 dentro do círculo
```

O nome da categoria sempre vem junto do ícone, então ninguém perde informação. Mesmo assim, a regra do projeto é 3:1 para ícone, e **cinco combinações não chegam lá**: Compras, Assinaturas e serviços e Outros no claro; Moradia e Educação no escuro. Alimentação no claro passa por 0,01 (3,01:1) e não tem folga.

**Proposta** (não aplicada, porque mexe em `tokens.json` e pede nova rodada do `check-contrast.mjs`):

1. Criar o token `icone` por categoria, usado só no desenho do ícone, com o tom sugerido na tabela acima. O círculo e o gráfico continuam com a cor do grupo, para a cor seguir sendo a mesma em toda parte.
2. Dar folga à Alimentação no claro, com um tom `icone` um pouco mais escuro.
3. Acrescentar ao `check-categorias.mjs` uma checagem do token novo, para o script falhar se alguém trocar uma cor sem rever o ícone [Suposição].

## Daltonismo e cor como único sinal

O `check-daltonismo.mjs` calcula a distância entre as cores no OKLab (multiplicada por 100), com a simulação de Machado et al. (2009) em severidade 1,0 [Conferir: Machado, Oliveira e Fernandes, 2009, IEEE TVCG]. Saída real:

```text
claro: menor distância entre dois dos 8 grupos da rosca e entre os 3 níveis de essencialidade
condição      grupos (par mais próximo)                                 essencialidade (par mais próximo)
visão normal  15.6 (Transporte × Assinaturas e serviços)                7.5 (Importante × Flexível)
protanopia    8.3 (Alimentação × Compras)                               7.7 (Importante × Flexível)
deuteranopia  8.3 (Moradia × Saúde)                                     7.4 (Importante × Flexível)
tritanopia    7.5 (Transporte × Saúde)                                  7.4 (Importante × Flexível)

escuro: menor distância entre dois dos 8 grupos da rosca e entre os 3 níveis de essencialidade
condição      grupos (par mais próximo)                                 essencialidade (par mais próximo)
visão normal  12.7 (Transporte × Assinaturas e serviços)                11.1 (Importante × Flexível)
protanopia    6.5 (Alimentação × Compras)                               11.2 (Importante × Flexível)
deuteranopia  6.6 (Saúde × Lazer)                                       11.2 (Importante × Flexível)
tritanopia    2.7 (Transporte × Assinaturas e serviços)                 11.2 (Importante × Flexível)
```

- **Tema claro:** os valores batem com a [Parte 1](01-revisao-das-decisoes.md), mudança 8 (15,6 para visão normal, 8,3 para protanopia e deuteranopia, 7,5 para tritanopia). O script reproduz o validador usado lá.
- **Tema escuro:** a faixa de luminosidade é mais estreita e as cores ficam mais próximas, em especial com tritanopia (2,7 entre Transporte e Assinaturas e serviços). É o motivo das três regras da [Parte 2](02-design-tokens.md): ordem fixa na rosca, que deixa esses dois grupos longe um do outro (posições 2 e 8); rótulo direto em cada fatia; 2 px de separação. No ranking, que ordena por valor e pode pôr os dois lado a lado, cada barra leva ícone e nome.
- **Essencialidade:** a distância entre Importante e Flexível é de só 7,4 a 7,7 no claro, e a razão de luminância entre os dois níveis é de 1,36:1. Os três níveis quase se confundem sem cor. É por isso que a escala nunca aparece sem as pintas (●●●, ●●○, ●○○) ou o nome ([Parte 1](01-revisao-das-decisoes.md), mudança 7).

Onde a cor carrega significado, sempre há um segundo sinal:

| Informação | Cor | Segundo sinal |
|---|---|---|
| Essencialidade | Três tons de Caramelo | Nome do nível e quantidade de pintas. Onde só cabem as pintas, o nome vai no rótulo de acessibilidade |
| Categoria | Cor do grupo | Ícone próprio e nome. Na rosca, rótulo direto e ranking ao lado |
| Entrada e saída | Mata nas entradas | Sinal `+` e `-` antes do valor. A saída fica na cor do texto |
| Erro e alerta | Urucum | Ícone e frase que diz o que fazer. A faixa de alerta tem ícone de aviso |
| Selecionado | `secondaryContainer` | Preenchimento diferente, peso de fonte maior e, no chip, o próprio estado de `FilterChip` |
| Banco | Faixa de 4 px na cor do banco | Nome do banco na linha e o logo de 20 px |
| Conexão do banco | Ponto Mata ou Milho | Texto: "Sincronizado hoje às 18:40" ou "Vence em 7 dias" |
| Mapa de calor | Escala de Caramelo | Rótulo por dia e abertura dos lançamentos ao tocar. Dia sem gasto é célula vazia com borda |
| Orçamento | Barra que enche | Número ao lado ("R$ 640,00 de R$ 960,00") e frase quando estoura |

## Texto

### Algarismos tabulares (`tnum`)

Todo valor em dinheiro usa `Inter` com `FontFeature.tabularFigures()`, nos estilos `valorDestaque`, `valorGrande` e `valorLinha` do [`granapaca_theme.dart`](tokens/granapaca_theme.dart). Efeito: as casas decimais ficam alinhadas na coluna do extrato, e o valor não "treme" na contagem do "Sobrou este mês". A `Plus Jakarta Sans` não é usada em valor.

### Escala de texto até 200%

O app respeita o tamanho de fonte do sistema (`MediaQuery.textScalerOf`) e não trava o fator [Conferir: api.flutter.dev, `TextScaler`]. O critério de aceite é: **a 200%, nenhum texto é cortado, nenhum alvo some e nenhuma ação fica fora da tela sem rolagem.**

| Componente | O que acontece a 200% |
|---|---|
| Linha de lançamento | O nome passa para até duas linhas e depois corta com reticências. Os detalhes (categoria, forma, banco) descem para uma segunda linha. **O valor nunca é cortado**: ele ganha linha própria à direita antes de qualquer outro texto |
| Valor em destaque | Os centavos acompanham a escala. Se o valor não couber, o cartão cresce em altura, nunca em largura |
| Barra de navegação | O rótulo continua sempre visível, como na [Parte 5](05-componentes.md). A barra cresce em altura. No trilho do desktop, o rótulo quebra em duas linhas |
| Chips de filtro | Quebram para a linha de baixo (`Wrap`), nunca rolam na horizontal escondendo opções |
| Botões | Crescem em altura, mantendo a pílula. O rótulo pode ter duas linhas |
| Folhas e diálogos | Rolam por dentro. O botão principal fica fixo no rodapé da folha |
| Rosca e barras | O gráfico mantém o tamanho. A legenda e o ranking, que são texto, é que crescem |
| Teclado numérico | As teclas mantêm 48 × 48 no mínimo e o valor digitado diminui para caber, até um piso legível [Suposição: 24 px] |

- **Tamanho mínimo:** o menor estilo é `labelSmall` (11 px), usado só em marcadores curtos. Nenhuma informação que só existe ali.
- **Altura de linha:** os estilos já trazem altura própria (`altura / tamanho`), que acompanha a escala.

## Alvos de toque

| Regra | Valor |
|---|---|
| Área mínima | 48 × 48 (`GranaEspaco.alvoDeToque`), mesmo quando o desenho é menor |
| Espaço entre alvos vizinhos | 8 no mínimo |
| Tema | `materialTapTargetSize: MaterialTapTargetSize.padded`, já em `granapaca_theme.dart` |
| Botão e campo | 48 de altura mínima e 56 de campo |

| Elemento | Desenho | Área de toque |
|---|---|---|
| Chip de filtro | 32 | 48 (o chip cresce na vertical em volta do desenho) |
| Olho de mostrar e esconder | 24 | 48 × 48 |
| Sino com contador | 24 | 48 × 48 |
| Interruptor e caixa de marcar | 24 a 32 | 48 × 48. O texto ao lado também toca |
| Faixa de data e filtros do extrato | 40 | 48 |
| Tecla do teclado numérico | maior que 48 | Teclas inteiras tocam, sem espaço morto |
| Barra e fatia dos gráficos | variável | A fatia pequena abre pelo item do ranking, que tem 48 de altura |
| Pintas de essencialidade | 12 de largura por pinta | Não tocam. Só informam |

Os componentes próprios (`LinhaDeLancamento`, `MarcadorDePintas` interativo, teclas) devem envolver o desenho em `ConstrainedBox` com mínimo de `GranaEspaco.alvoDeToque`.

## Foco e teclado

O desktop e a demo web são navegáveis só pelo teclado.

| Item | Regra |
|---|---|
| Anel de foco | 2 px em `primary`, afastado 2 do componente. Medido acima: no mínimo 4,75:1 |
| Ordem | A mesma ordem de leitura: de cima para baixo e da esquerda para a direita. Na barra, Início, Extrato, Gastos e Paçoca, com o "+" no meio |
| Ativar | `Enter` e `Espaço`. `Esc` fecha folha, diálogo e menu |
| Folha e diálogo | Prendem o foco enquanto abertos. O primeiro foco vai para o título. Ao fechar, o foco volta ao elemento que abriu |
| Lista com detalhe ao lado (desktop) | Setas sobem e descem na lista. `Enter` abre o detalhe e leva o foco até ele. `Esc` devolve o foco à linha |
| Segmentos e abas | Setas trocam a opção. `Tab` sai do grupo |
| Campos | `Tab` avança, `Shift + Tab` volta. O erro aparece ao sair do campo e fica associado a ele |
| Atalhos | `/` foca a busca do extrato e `Ctrl + Z` desfaz o último ajuste [Suposição]. Todo atalho tem equivalente na tela |

Implementação prevista: `FocusTraversalGroup`, `Shortcuts` e `Actions`, e `FocusableActionDetector` nos componentes próprios [Conferir: api.flutter.dev, sistema de foco].

## Leitor de tela

A regra geral é a do briefing: cada gráfico tem resumo em texto e cada ícone tem rótulo. Valores monetários são lidos por extenso, em reais e centavos, com o sentido da movimentação.

| Elemento | O que o leitor diz |
|---|---|
| Lançamento | "Mercado da Vila, alimentação, essencial, débito no Banco Ipê, saída de 187 reais e 43 centavos". Uma frase só, no `Semantics` da linha, com os filhos fora da leitura |
| Entrada | "Salário, entrada, Pix no Banco Ipê, 6.200 reais" |
| Valor oculto | "valor oculto", no lugar de "R$ •••". O `Semantics` leva `excludeSemantics: true` para as pintas não serem lidas uma a uma |
| Olho | "Mostrar valores" ou "Esconder valores", com o estado atual |
| Pintas | "Essencial", "Importante" ou "Flexível". Nunca "três pintas" |
| Sino | "Alertas: 2 novos" |
| Rosca | Resumo único: "Para onde foi, em novembro: Moradia, 37% dos gastos; Alimentação, 20%; Transporte, 11%..." [Suposição: percentuais inteiros, ajustados para somar 100]. Com valores ocultos, só os percentuais |
| Ranking | Cada barra é um item de lista: "Moradia, 37% dos gastos, 1.800 reais". Toque abre os lançamentos |
| 50/30/20 | "Necessidades, 45% da renda. Desejos, 34%. Poupança, 21%" |
| Mapa de calor | Cada dia: "5 de novembro, gastou 312 reais" ou "5 de novembro, sem gastos". Com valores ocultos: "nível 4 de 5" |
| Contagem do "Sobrou este mês" | O leitor recebe só o valor final. Os números intermediários ficam fora (`ExcludeSemantics` na animação e o valor final no `Semantics`) |
| Paçoca decorativa | Fora da leitura, quando a frase ao lado já diz tudo |
| Paçoca como único sinal | Com rótulo, como "A Paçoca está dormindo: sem internet" |
| Resposta do chat | Cartão lido como frase: "Você gastou 960 reais com alimentação em novembro, de 1 a 26. Ver transações." |
| Aviso de minimização | Texto fixo na tela, lido junto da conversa, não só ao tocar |
| Histórico de ajustes | Lista com data, o que mudou, "de" e "para", e o botão "Desfazer" com o nome do ajuste |
| Teclado numérico | Cada tecla pelo algarismo. O valor digitado é lido como "12 reais e 50 centavos" |

- **Anúncios:** o aviso rápido e a faixa de alerta são anunciados quando aparecem. A faixa usa `Semantics(liveRegion: true)` [Conferir: api.flutter.dev, `SemanticsProperties.liveRegion`]. Mensagens novas do chat também.
- **Tempo:** o aviso rápido some em 4 segundos. Com leitor de tela ou navegação por teclado ativos (`MediaQuery.accessibleNavigationOf`), o aviso com "Desfazer" fica mais tempo, por exemplo 10 segundos [Suposição]. O Desfazer também existe no histórico, sem prazo.
- **Erros:** a frase do erro vem com o campo e diz o que fazer. Erro que impede continuar não vai em aviso rápido.
- **Idioma:** `Locale('pt', 'BR')` no app, para o leitor ler "R$" e as datas direito.
- **Demo web:** a árvore de acessibilidade do Flutter Web só liga depois de uma ação do leitor de tela, e vale conferir se o botão de ativação aparece [Conferir: docs.flutter.dev, acessibilidade na web].

## Movimento

Com "reduzir movimento" ligado (`MediaQuery.disableAnimationsOf(context)`), `GranaMovimento.ou` devolve `Duration.zero`.

| Animação | Com o movimento normal | Com "reduzir movimento" |
|---|---|---|
| Contagem do "Sobrou este mês" (900 ms) | Sobe até o valor | Mostra o valor final. Só roda com os valores visíveis |
| Chuva de moedinhas (1200 ms) | Meta batida | Não há. Fica o texto e a Paçoca parada comemorando |
| Paçoca (Rive) | Máquina de estados `pacoca` | SVG parado da expressão, com fade de 150 ms |
| Criação de conta (olhar, patas, escudo, pulinho) | Coreografia da [Parte 3](03-mascote.md) | Pose estática de cada etapa |
| Esqueleto e pintas de carregamento | Pulsam a cada 1 s | Parados, com o texto "Carregando" |
| Puxar para atualizar | Paçoca mergulhando | Paçoca parada e a frase "Atualizando" |
| Troca de tela e de folha (300 e 400 ms) | Deslize e fade | Troca direta ou fade de 150 ms |

- Nenhuma animação do app pisca mais de três vezes por segundo.
- Vibração ao salvar é complemento. Quem desliga a vibração no sistema continua vendo o aviso na tela.

## Checklist por tela

Legenda: ✅ garantido pelo desenho e pelos tokens medidos; ☐ ainda precisa ser conferido no app ou no aparelho.

| Tela | Folha | Contraste (tokens) | Cor com segundo sinal | `Semantics` definida | Texto a 200% | Aparelho real |
|---|---|---|---|---|---|---|
| Criação de conta e guia | [trilha 1](telas/trilha-1-claro.svg), [trilha 2](telas/trilha-2-claro.svg) | ✅ | ✅ | ✅ | ☐ | ☐ |
| Início | [inicio](telas/inicio-claro.svg), [desktop](telas/inicio-desktop-claro.svg) | ✅ | ✅ | ✅ | ☐ | ☐ |
| Extrato | `telas/extrato-*.svg`, `telas/extrato-desktop-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |
| Detalhe e correção | `telas/detalhe-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |
| Gastos | `telas/gastos-*.svg`, `telas/gastos-desktop-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |
| Chat da Paçoca | `telas/chat-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |
| Comprovantes e dinheiro físico | `telas/comprovantes-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |
| Planejamento e alertas | `telas/planejamento-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |
| Configurações e modo demo | `telas/config-*.svg` | ✅ | ✅ | ✅ | ☐ | ☐ |

Em todas as folhas, os sufixos são `-claro` e `-escuro`. Os links das Partes [7](07-telas-b.md) e [8](08-telas-c.md) levam às imagens. "Contraste" vale porque as telas só usam cores de `tokens.json`; as peças ilustradas da Paçoca têm as próprias cores e ficam fora da conta.

Pendências antes de dar a acessibilidade por fechada:

- [ ] Aplicar a proposta dos ícones de categoria e rodar de novo os três scripts.
- [ ] Testar com **TalkBack** no Android e **VoiceOver** no iOS, em Início, Extrato, Detalhe, Gastos e Chat [Conferir: em aparelho real].
- [ ] Testar o desktop só com teclado, incluindo foco ao abrir e fechar o detalhe e a folha.
- [ ] Testar com texto a 200% em tela de 360 de largura, nas telas da tabela acima.
- [ ] Conferir se o app pega a opção "reduzir movimento" nos três sistemas (Android, iOS e desktop) e na demo web [Conferir: comportamento por plataforma].
- [ ] Conferir contraste dentro do app em modo de alto contraste do sistema, se a plataforma oferecer [Conferir: Flutter, `MediaQuery.highContrast`].
- [ ] Gravar os `Semantics` em teste de widget, para a frase do lançamento e o "valor oculto" não regredirem.

## Próximo

[Parte 12](12-passagem-flutter.md): passagem para o Flutter.
