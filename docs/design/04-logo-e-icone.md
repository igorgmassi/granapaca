# Parte 4: Logo e ícone

O logo é o nome GranaPaCá em letreiro arredondado, Caramelo, com o acento do á desenhado como uma moedinha caindo. O ícone é a cabeça da Paçoca de perfil sobre Caramelo, com três pintas creme em linha no pescoço. Tudo está em SVG na pasta [`logo`](logo/).

- **Data:** 2026-11-10
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

A cabeça da Paçoca de perfil, com o mesmo desenho da [mascote](03-mascote.md), e três pintas creme alongadas em linha no pescoço. As pintas são elipses, não círculos: redondas e com anel, pareciam botões de camisa. O pescoço termina arredondado, para o símbolo ficar inteiro sem o fundo do ícone.

## Ícone do app

| iOS claro | iOS escuro | iOS tingido | Android | Android temático |
|---|---|---|---|---|
| <img src="logo/icone-ios-claro.svg" width="120" alt="Ícone iOS claro"> | <img src="logo/icone-ios-escuro.svg" width="120" alt="Ícone iOS escuro"> | <img src="logo/icone-ios-tingido.svg" width="120" alt="Ícone iOS tingido"> | <img src="logo/icone-android-frente.svg" width="120" alt="Frente do ícone Android"> | <img src="logo/icone-android-mono.svg" width="120" alt="Ícone Android monocromático"> |

No ícone, a cabeça fica num caramelo claro (#E3A775), porque a cor do corpo da mascote some contra o fundo Caramelo. O pescoço sai pela borda de baixo, como um busto.

| Arquivo | Plataforma | O que é |
|---|---|---|
| `icone-ios-claro.svg` | iOS | Quadro inteiro de 1024 px; o sistema arredonda os cantos. |
| `icone-ios-escuro.svg` | iOS | Aparência escura, sobre o fundo Paçoca escuro (#17110D). |
| `icone-ios-tingido.svg` | iOS | Aparência tingida: tons de cinza sobre fundo transparente; o sistema aplica a cor. |
| `icone-android-fundo.svg` | Android | Camada de fundo do ícone adaptativo: Caramelo chapado. |
| `icone-android-frente.svg` | Android | Camada da frente. O essencial fica no círculo seguro de 66 dp dentro da camada de 108 dp. |
| `icone-android-mono.svg` | Android | Camada monocromática dos ícones temáticos: só a forma, com olho e pintas vazados. |
| `favicon.svg` | Web | Demo web: cantos arredondados, sem bigodes e com a cabeça maior, para 16 a 32 px. |

### Tamanhos pequenos

| 48 px | 24 px | Favicon 32 px | Favicon 16 px |
|---|---|---|---|
| <img src="logo/icone-ios-claro.svg" width="48" alt="Ícone em 48 px"> | <img src="logo/icone-ios-claro.svg" width="24" alt="Ícone em 24 px"> | <img src="logo/favicon.svg" width="32" alt="Favicon em 32 px"> | <img src="logo/favicon.svg" width="16" alt="Favicon em 16 px"> |

Em 48 px a cabeça, o olho e as pintas aparecem, como o briefing exige. Em 16 px sobra a silhueta, e por isso o favicon é um desenho próprio.

## Cores e contraste

| Par | Contraste |
|---|---|
| Logo Caramelo sobre o fundo Paçoca | 5,21:1 |
| Logo Caramelo sobre branco | 5,65:1 |
| Logo escuro sobre o fundo escuro | 8,60:1 |
| Cabeça do ícone sobre o fundo Caramelo | 2,70:1 |
| Cabeça do ícone sobre o fundo escuro | 8,95:1 |
| Símbolo sobre o fundo Paçoca | 3,74:1 |

A cabeça do ícone fica abaixo de 3:1 contra o Caramelo. Ela se separa do fundo também pelo olho escuro, pelas pintas e pelo contorno, e a folha de testes mostrou a silhueta legível de 24 px para cima. O ícone usa 7 cores, contando o fundo: é um mascote, não um logo abstrato, e cada cor tem um papel.

## Usos proibidos

- Recolorir fora das versões desta página, esticar, girar ou inclinar.
- Pôr contorno, sombra, brilho ou degradê.
- Trocar o letreiro por texto digitado em Fredoka ou em outra fonte.
- Separar a moedinha do "a", ou usá-la como acento em outras palavras.
- Usar o logo horizontal abaixo do tamanho mínimo, em vez do símbolo.
- Pôr o símbolo sobre Caramelo: nesse fundo, use o ícone.

## A conferir

- **Android:** as medidas das camadas (108 dp, área visível de 72 dp e círculo seguro de 66 dp) e o formato aceito para a camada monocromática [Conferir: developer.android.com, ícones adaptativos].
- **iOS:** as três aparências (clara, escura e tingida) e os ícones em camadas do iOS 26, feitos no Icon Composer [Conferir: Apple Human Interface Guidelines, App icons].
- **Exportação:** o pacote flutter_launcher_icons pede imagens PNG [Conferir: pub.dev/packages/flutter_launcher_icons]. Os PNGs saem destes SVGs na Parte 12, com o script `render_png.py` da skill logo-design.
- **Traços:** o letreiro e os bigodes são traços (stroke). Para gravação, recorte ou bordado, expanda os traços num editor vetorial. O ícone monocromático usa máscara, então ele é exportado em PNG.

## Próximo

Parte 5: biblioteca de componentes.
