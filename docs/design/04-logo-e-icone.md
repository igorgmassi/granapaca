# Parte 4: Logo e ícone

O logo é o nome GranaPaCá em letreiro arredondado, Caramelo, com o acento do á desenhado como uma moedinha caindo. O ícone é a pochete verde da Paçoca sobre Caramelo, com a fivela de moeda e três pintas creme costuradas na frente. Tudo está em SVG na pasta [`logo`](logo/).

- **Data:** 2026-11-10; símbolo e ícone refeitos em 2026-11-11
- **Para regenerar:** `node docs/design/logo/gerar-logo.mjs`
- **Conferido com:** a skill logo-design (auditoria dos SVGs e folha de testes com tamanhos, fundos, uma cor, invertido, borrado, espelhado e girado).

## Logo

| Versão | Arquivo | Onde usar |
|---|---|---|
| ![Logo colorido](logo/logo-cor.svg) | `logo-cor.svg` | Fundo claro: README, telas, apresentação |
| ![Logo sobre fundo escuro](logo/logo-escuro.svg) | `logo-escuro.svg` | Fundo escuro e tema escuro |
| ![Logo em uma cor](logo/logo-mono.svg) | `logo-mono.svg` | Uma cor só: carimbo, gravação, impressão em preto. Usa a cor do texto em volta (`currentColor`). |
| <img src="logo/logo-empilhado.svg" width="180" alt="Logo empilhado"> | `logo-empilhado.svg` | Espaços estreitos: tela de abertura, avatar de perfil, capa |

**Como foi construído.** As letras não são a fonte Fredoka digitada: são traços redondos de espessura única, desenhados na geometria da Fredoka SemiBold. Assim o logo sai igual em qualquer lugar, sem depender de fonte instalada, e o acento vira desenho. O "a" é de um andar só, como no estilo arredondado do mascote. O P e o C maiúsculos marcam as duas palavras do trocadilho.

**A moedinha.** Ela cai na direção do acento agudo, com dois rastros para cima e para a direita: o "pra cá" em forma de desenho. Na versão colorida é Milho com anel Caramelo. Na versão de uma cor, vira anel e miolo vazados, para funcionar sobre qualquer fundo.

**Revisão do briefing.** O briefing pede "Grana PaCá" com espaço. Mantive "GranaPaCá" junto, como no repositório e no README ([Parte 1](01-revisao-das-decisoes.md), mudança 15). Se preferir com espaço, só o espaço entre "Grana" e "PaCá" muda no gerador.

### Área de respiro

![Área de respiro do logo](logo/logo-respiro.svg)

A área livre em volta do logo é **x**, a altura do "a" minúsculo: metade da altura do logo. Nenhum texto, borda ou outro logo entra nela.

### Tamanhos mínimos

| Versão | Tela | Impressão |
|---|---|---|
| Logo horizontal | 24 px de altura | 8 mm de altura |
| Logo empilhado | 64 px de altura | 20 mm de altura |
| Símbolo | 32 px | 10 mm |
| Abaixo disso | Use o favicon | — |

Na folha de testes, o logo horizontal ainda lê com 16 px de altura. O mínimo de 24 px deixa folga para a moedinha, que vira um ponto abaixo disso.

## Símbolo

<img src="logo/simbolo.svg" width="160" alt="Símbolo do GranaPaCá">

A pochete da Paçoca: a bolsa verde Mata, a tampa num verde mais escuro, a fivela com a moedinha do logo e três pintas creme alongadas, como as fileiras de pintas da paca. As pintas são traços arredondados, não círculos: redondas e com anel, pareciam botões de camisa. No símbolo a alça é um trecho curto do mesmo arco do ícone, com as pontas arredondadas. Com as pontas subindo mais, ela parecia chifre ou bigode.

## Ícone do app

### Por que a pochete

O primeiro ícone era a cabeça da Paçoca de perfil. Em 48 px ela parecia um bicho marrom qualquer. As cinco versões ilustradas feitas depois no Gemini ficaram detalhadas demais para o tamanho, ou engraçadinhas demais para um app de dinheiro. Ícone de app pede uma ideia só, numa forma compacta. Comparei quatro caminhos abstratos: a pochete; a silhueta da paca, que parecia porquinho e depois anta; os olhos brilhando na toca; e o G do letreiro com uma moeda. A pochete ganhou porque:

- é a assinatura visual da Paçoca, presente em todas as poses da [mascote](03-mascote.md);
- guarda a grana, e a fivela é a moedinha do logo;
- leva as pintas da paca, costuradas na frente;
- o verde Mata é o oposto do Caramelo no círculo de cores.

| iOS claro | iOS escuro | iOS tingido | Android | Android temático |
|---|---|---|---|---|
| <img src="logo/icone-ios-claro.svg" width="120" alt="Ícone iOS claro"> | <img src="logo/icone-ios-escuro.svg" width="120" alt="Ícone iOS escuro"> | <img src="logo/icone-ios-tingido.svg" width="120" alt="Ícone iOS tingido"> | <img src="logo/icone-android-frente.svg" width="120" alt="Frente do ícone Android"> | <img src="logo/icone-android-mono.svg" width="120" alt="Ícone Android monocromático"> |

A pochete fica sobre um disco creme, no centro óptico (um pouco acima do meio). A alça atravessa o disco e sai pelas bordas, como um cinto. O disco separa a bolsa verde do Caramelo (veja [Cores e contraste](#cores-e-contraste)). No iOS o quadro aparece inteiro. No Android só os 72 dp do meio aparecem, então a camada da frente usa a mesma composição em 2/3 do tamanho, e o disco inteiro cabe no círculo seguro.

| Arquivo | Plataforma | O que é |
|---|---|---|
| `icone-ios-claro.svg` | iOS | Quadro inteiro de 1024 px; o sistema arredonda os cantos. |
| `icone-ios-escuro.svg` | iOS | Aparência escura, sobre o fundo Paçoca escuro (#17110D). |
| `icone-ios-tingido.svg` | iOS | Aparência tingida: tons de cinza sobre fundo transparente; o sistema aplica a cor. |
| `icone-android-fundo.svg` | Android | Camada de fundo do ícone adaptativo: Caramelo chapado. |
| `icone-android-frente.svg` | Android | Camada da frente. O essencial fica no círculo seguro de 66 dp dentro da camada de 108 dp. |
| `icone-android-mono.svg` | Android | Camada monocromática dos ícones temáticos: só a forma, com a linha da tampa, a moeda e as pintas vazadas. |
| `favicon.svg` | Web | Demo web: cantos arredondados, sem as pintas, com o disco e a pochete maiores, para 16 a 32 px. |

### Tamanhos pequenos

| 48 px | 24 px | Favicon 32 px | Favicon 16 px |
|---|---|---|---|
| <img src="logo/icone-ios-claro.svg" width="48" alt="Ícone em 48 px"> | <img src="logo/icone-ios-claro.svg" width="24" alt="Ícone em 24 px"> | <img src="logo/favicon.svg" width="32" alt="Favicon em 32 px"> | <img src="logo/favicon.svg" width="16" alt="Favicon em 16 px"> |

Em 48 px aparecem a bolsa, a tampa, a moeda e as pintas. Em 24 px as pintas viram uma linha clara e a moeda vira um ponto dourado, mas a forma da pochete continua. O favicon tira as pintas e aumenta a bolsa para ser lido em 16 px.

## Cores e contraste

| Par | Contraste |
|---|---|
| Logo Caramelo sobre o fundo Paçoca | 5,21:1 |
| Logo Caramelo sobre branco | 5,65:1 |
| Logo escuro sobre o fundo escuro | 8,60:1 |
| Bolsa verde sobre o fundo Caramelo | 1,01:1 (por isso o disco) |
| Disco creme sobre o fundo Caramelo | 4,61:1 |
| Bolsa sobre o disco creme, e pintas sobre a bolsa | 4,56:1 |
| Bolsa sobre o fundo escuro | 3,35:1 |
| Símbolo sobre o fundo Paçoca: tampa e alça | 7,50:1 |
| Símbolo sobre o fundo Paçoca: bolsa | 5,15:1 |

O verde Mata e o Caramelo têm quase a mesma luminância. Direto sobre o Caramelo, a pochete só se separa do fundo pela cor: some em escala de cinza e vira uma mancha com 32 px. Testei três correções em cor, em cinza e com simulação de deuteranopia e de protanopia (Machado 2009): um anel creme em volta da bolsa, um disco creme atrás dela e um fundo escuro. O escolhido foi o disco. Com ele, a bolsa fica a 4,56:1 do creme e o creme a 4,61:1 do Caramelo. A alça, onde passa fora do disco, fica em 1,44:1, mas é detalhe. No fundo escuro a bolsa já passa de 3:1, então o ícone escuro não tem disco. A moeda fica em 2,61:1 sobre a bolsa, mas ela é detalhe: a forma que identifica o ícone é a pochete. O ícone usa 7 cores, contando o fundo, e cada cor tem um papel.

## Usos proibidos

- Recolorir fora das versões desta página, esticar, girar ou inclinar.
- Pôr contorno, sombra, brilho ou degradê.- Trocar o letreiro por texto digitado em Fredoka ou em outra fonte.
- Separar a moedinha do "a", ou usá-la como acento em outras palavras.
- Usar o logo horizontal abaixo do tamanho mínimo, em vez do símbolo.
- Pôr o símbolo sobre Caramelo: nesse fundo, use o ícone, com o disco creme.
- Tirar o disco do ícone claro, ou pôr o disco no ícone escuro ou no símbolo.

## A conferir

- **Android:** as medidas das camadas (108 dp, área visível de 72 dp e círculo seguro de 66 dp) e o formato aceito para a camada monocromática [Conferir: developer.android.com, ícones adaptativos].
- **iOS:** as três aparências (clara, escura e tingida) e os ícones em camadas do iOS 26, feitos no Icon Composer [Conferir: Apple Human Interface Guidelines, App icons].
- **Exportação:** o pacote flutter_launcher_icons pede imagens PNG [Conferir: pub.dev/packages/flutter_launcher_icons]. Os PNGs saem destes SVGs na Parte 12, com o script `render_png.py` da skill logo-design.
- **Traços:** o letreiro e a alça da pochete são traços (stroke). Para gravação, recorte ou bordado, expanda os traços num editor vetorial. O ícone monocromático usa máscara, então ele é exportado em PNG.

## Próximo

Parte 5: biblioteca de componentes.
