# app

App Flutter do GranaPaCá: Android, iOS, Windows, macOS e Linux, mais a demo em Flutter Web com dados sintéticos.

## Estado

Esqueleto da Fase 0 (#4): tema neutro do Material 3 (claro e escuro) e uma tela inicial no **modo demo**. Os dados vêm de `lib/demo/demo_data.dart`, gerados no próprio app com semente fixa, sem backend e sem nenhum dado real. Os tokens do design entram no #12.

## Rodar

O CI usa o Flutter 3.50.0 (Dart 3.14.0).

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome   # ou windows, macos, linux, android, ios
```
