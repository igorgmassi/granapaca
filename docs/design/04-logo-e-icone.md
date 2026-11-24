# Parte 4: Logo e ícone

O logo oficial é a **Opção B — Paca Deitada Evoluída**: o nome **Grana PaCá** em tipografia geométrica limpa sem serifa (`Plus Jakarta Sans Bold`), com "Grana" em Cacau (ou Off-white no escuro), "PaCá" em Terracota (ou Âmbar no escuro) e a paca pintada **sem contorno preto** descansando tranquilamente sobre "PaCá". O ícone do app usa a própria silhueta limpa da paca deitada. Tudo está em SVG na pasta [`logo`](logo/).

- **Data:** 2026-11-10; atualizado para Toca Editorial (Opção B) em 2026-11-24
- **Para regenerar:** `node docs/design/logo/gerar-logo.mjs`

## Logo

| Versão | Arquivo | Onde usar |
|---|---|---|
| <img src="logo/logo-cor.svg" width="360" alt="Logo colorido"> | `logo-cor.svg` | Fundo claro (`#FAF8F5` ou `#FFFFFF`): README, telas e apresentação |
| <img src="logo/logo-escuro.svg" width="360" alt="Logo sobre fundo escuro"> | `logo-escuro.svg` | Fundo escuro (`#14110F`) e tema escuro |
| <img src="logo/logo-mono.svg" width="360" alt="Logo em uma cor"> | `logo-mono.svg` | Uma cor só (`currentColor`): impressão, carimbo e marca d'água |

**O que mudou na revisão Toca Editorial:**
- A serifa pesada anterior foi substituída pela família `Plus Jakarta Sans Bold`, unificando logo e interface.
- A paca sobre `PaCá` mantém o gesto afetivo original, agora **100% sem contorno preto**, com focinho suavemente alongado de paca, olho fechado sereno e fileiras limpas de pintas vazadas.
- A pochete saiu tanto da mascote quanto do ícone: a própria paca deitada entrega leitura imediata e contraste superior em qualquer tamanho.

### Área de respiro

![Área de respiro do logo](logo/logo-respiro.svg)

A área livre em volta do logo equivale à altura da letra "a" minúscula. Nenhum texto, borda ou outro elemento entra nela.

### Tamanhos mínimos

| Uso | Tela | Impressão |
|---|---|---|
| Logo completo | 120 px de largura | 30 mm de largura |
| Abaixo disso | Use o símbolo ou o ícone do app | — |

## Símbolo e ícone do app (Paca Deitada)

<img src="logo/simbolo.svg" width="140" alt="Símbolo do GranaPaCá">

A silhueta única da paca deitada funciona nativamente sem disco intermediário: creme algodão (`#FAF8F5`) sobre Terracota (`#A84C19`) no claro (**5,37:1**), Âmbar (`#E5965C`) sobre Obsidiana (`#1E1A17`) no escuro (**7,28:1**) e máscara vazada pura nos ícones temáticos do Android.

| iOS claro | iOS escuro | iOS tingido | Android (frente) | Android temático |
|---|---|---|---|---|
| <img src="logo/icone-ios-claro.svg" width="120" alt="Ícone iOS claro"> | <img src="logo/icone-ios-escuro.svg" width="120" alt="Ícone iOS escuro"> | <img src="logo/icone-ios-tingido.svg" width="120" alt="Ícone iOS tingido"> | <img src="logo/icone-android-frente.svg" width="120" alt="Frente do ícone Android"> | <img src="logo/icone-android-mono.svg" width="120" alt="Ícone Android monocromático"> |

| Arquivo | Plataforma | O que é |
|---|---|---|
| `icone-ios-claro.svg` | iOS | Terracota `#A84C19` + paca creme `#FAF8F5` (quadro 1024 px). |
| `icone-ios-escuro.svg` | iOS | Obsidiana `#1E1A17` + paca âmbar `#E5965C`. |
| `icone-ios-tingido.svg` | iOS | Silhueta vazada neutra sobre fundo transparente para o tingimento do sistema. |
| `icone-android-fundo.svg` | Android | Camada de fundo sólida em Terracota `#A84C19`. |
| `icone-android-frente.svg` | Android | Paca creme centralizada dentro do círculo seguro de 66 dp (camada 108 dp). |
| `icone-android-mono.svg` | Android | Camada monocromática vazada (3 pintas ampliadas para nitidez em ícones temáticos). |
| `favicon.svg` | Web | Versão com cantos arredondados e 3 pintas maiores, legível em 16 px e 32 px. |

### Tamanhos pequenos

| 48 px | 24 px | Favicon 32 px | Favicon 16 px |
|---|---|---|---|
| <img src="logo/icone-ios-claro.svg" width="48" alt="Ícone em 48 px"> | <img src="logo/icone-ios-claro.svg" width="24" alt="Ícone em 24 px"> | <img src="logo/favicon.svg" width="32" alt="Favicon em 32 px"> | <img src="logo/favicon.svg" width="16" alt="Favicon em 16 px"> |

## Cores e contraste

| Par | Contraste |
|---|---|
| Logo claro: "Grana" (`#231C16`) sobre Algodão (`#FAF8F5`) | 15,86:1 |
| Logo claro: "PaCá" (`#A84C19`) sobre Algodão (`#FAF8F5`) | 5,37:1 |
| Logo escuro: "Grana" (`#F5F1EC`) sobre Toca Noturna (`#14110F`) | 16,72:1 |
| Logo escuro: "PaCá" e paca (`#E5965C`) sobre Toca Noturna (`#14110F`) | 7,71:1 |
| Ícone claro: paca creme (`#FAF8F5`) sobre Terracota (`#A84C19`) | 5,37:1 |
| Ícone escuro: paca âmbar (`#E5965C`) sobre Obsidiana (`#1E1A17`) | 7,28:1 |

## Usos proibidos

- Recolorir fora das versões desta página, esticar, girar ou inclinar.
- Colocar contorno preto ao redor da paca, sombra pesada ou brilho artificial.
- Separar a paca do wordmark ou recolocar a pochete antiga sobre o logo.
- Usar o logo abaixo de 120 px de largura (trocar pelo símbolo ou ícone).

## Próximo

[Parte 5](05-componentes.md): biblioteca de componentes.
