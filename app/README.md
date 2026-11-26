# app

App Flutter do GranaPaCá: Android, iOS, Windows, macOS e Linux, mais a demo em Flutter Web com dados sintéticos.

## Estado

Demo navegável completa da Fase 1 (com tema claro e escuro na paleta *Mata e Fruta*):

- **Início** (RF-16, RF-05): resumo consolidado do mês, saldo somado das contas, fatura aberta à parte, barra de essencialidade (*Essencial*, *Importante*, *Flexível*), bancos clicáveis, modo esconder valores (`R$ •••` e leitor de tela `"valor oculto"`) e layout responsivo em duas colunas no desktop.
- **Bancos e cartões** (RF-17, RF-20): alternância entre "Todos" e cada banco, contas, cartões com 4 últimos dígitos, faturas aberta e fechadas e parcelas (`3 de 10`).
- **Extrato, correções e regras** (RF-18, RF-19, RF-24..27, RF-31): filtros combinados, busca sem acento na descrição original ou corrigida, paginação incremental, correção com justificativa e desfazer *append-only*, aplicação às semelhantes e gestão de regras.
- **Gastos** (RF-34, RF-35, RF-36): rosca interativa por categoria (até 5 fatias + demais) e ranking em barras horizontais sincronizados com os filtros de período, banco e conta.
- **Guia inicial, demo e alertas** (RF-08, RF-56, RF-63): trilha de primeiro acesso com etapas bloqueadas na demo, guia de perfil (ocupação, casa e transporte) com revisão das regras e caixa de entrada de alertas.

Os dados vêm de `lib/demo/demo_data.dart`, gerados no próprio app de forma determinística, sem backend, sem chamadas de rede e sem nenhum dado real.

## Rodar

O CI usa o Flutter 3.50.0 (Dart 3.14.0).

```bash
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
flutter run -d chrome   # ou windows, macos, linux, android, ios
```
