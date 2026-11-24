import 'package:material_ui/material_ui.dart';

import 'finance/model.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'state/app_state.dart';
import 'state/preferences_store.dart';
import 'theme/grana_theme.dart';

void main() {
  runApp(const GranaPaCaApp());
}

class GranaPaCaApp extends StatefulWidget {
  const GranaPaCaApp({
    super.key,
    this.dataset,
    this.preferencesStore,
    this.simulateNoConnections = false,
    this.startInOnboarding = false,
  });

  final Dataset? dataset;
  final PreferencesStore? preferencesStore;
  final bool simulateNoConnections;
  final bool startInOnboarding;

  @override
  State<GranaPaCaApp> createState() => _GranaPaCaAppState();
}

class _GranaPaCaAppState extends State<GranaPaCaApp> {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _state = AppState(
      dataset: widget.dataset,
      preferencesStore: widget.preferencesStore,
      simulateNoConnections: widget.simulateNoConnections,
    );
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
          title: 'GranaPaCá',
          debugShowCheckedModeBanner: false,
          theme: granaLightTheme(),
          darkTheme: granaDarkTheme(),
          themeMode: _state.themeMode,
          home: widget.startInOnboarding
              ? const OnboardingScreen(profileOnly: false)
              : const AppShell(),
        ),
      ),
    );
  }
}
