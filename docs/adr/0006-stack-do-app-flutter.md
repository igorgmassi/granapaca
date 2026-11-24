# ADR-006: Stack do app Flutter

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O GranaPaCá entrega uma única base de código cliente para Android, iOS, Windows, macOS, Linux e demo web no GitHub Pages (RF-63). No MVP, o app precisa compilar de forma previsível nas seis plataformas no CI, acompanhar atualizações do Flutter 3 sem quebras causadas por pacotes de terceiros e oferecer gráficos financeiros legíveis (rosca por categoria, ranking horizontal e mapa de calor) alinhados à identidade visual do projeto.

## Decisão

Adotar uma stack enxuta em **Flutter 3** (Dart 3) com o mínimo de dependências externas no MVP:

- **Interface:** Material 3 via `material_ui`, com tokens próprios de cor, tipografia e espaçamento em `app/lib/theme/` e navegação responsiva (`NavigationBar` no mobile e `NavigationRail` no desktop em `AppShell`).
- **Estado:** `ChangeNotifier` (`AppState`) exposto por `InheritedNotifier` (`AppScope`) e `ListenableBuilder`, sem Riverpod nem Bloc no MVP. A persistência leve de preferências usa abstração própria por plataforma (`preferences_store`).
- **Gráficos e visualizações:** gráficos interativos (rosca por categoria e barras de ranking) desenhados com `CustomPaint` e widgets nativos do Flutter, junto a um mapa de calor calendário próprio, dispensando bibliotecas externas de gráficos como `fl_chart`.
- **Navegação:** shell com abas e `Navigator` padrão para telas de detalhe e folhas modais no MVP; roteamento declarativo (`go_router`) só entra se o uso de deep links justificar o custo.

## Alternativas consideradas

- **Riverpod 3 ou Bloc 9 desde o dia zero:** trazem geração de código (`build_runner`) ou cerimônia extra e aumentam o acoplamento a versões específicas do Dart/Flutter para um estado que, no MVP, é pequeno e centralizado.
- **`fl_chart` para gráficos:** acelera o primeiro protótipo, mas costuma atrasar em atualizações de SDK do Flutter e limita o controle fino de acessibilidade, toque em fatias e consistência visual com os tokens do design system.
- **`go_router` imediato:** adiciona abstração e dependência a mais para uma estrutura de quatro abas sem rotas profundas na demo web ou no MVP.

## Consequências

- `app/pubspec.yaml` permanece mínimo, com build rápido e menos risco de quebra no CI multiplataforma (web, Linux, Android, Windows, macOS e iOS).
- O time mantém controle total sobre o desenho, a acessibilidade e os testes de widget dos gráficos e do mapa de calor.
- Conforme novos módulos do app crescerem (cache offline, sincronização, chat com IA e comprovantes), o estado deve ser fatiado em múltiplos `ChangeNotifier` coesos — e uma eventual migração para Riverpod ou `go_router` exigirá um novo ADR.
