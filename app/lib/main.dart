import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api/api_models.dart';
import 'api/granapaca_api_client.dart';
import 'finance/model.dart';
import 'screens/app_lock_screen.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/server_auth_screen.dart';
import 'security/app_lock.dart';
import 'state/app_state.dart';
import 'state/preferences_store.dart';
import 'storage/encrypted_cache.dart';
import 'theme/grana_theme.dart';

void main() {
  runApp(const GranaPaCaApp());
}

class GranaPaCaApp extends StatefulWidget {
  const GranaPaCaApp({
    super.key,
    this.dataset,
    this.preferencesStore,
    this.apiClient,
    this.encryptedCache,
    this.appLock,
    this.simulateNoConnections = false,
    this.startInOnboarding = false,
    this.startInServerAuth = false,
    this.initialMode,
    this.initialServerUrl,
    this.initialConnections,
    this.initialOffline = false,
    this.initialLastSyncedAt,
  });

  final Dataset? dataset;
  final PreferencesStore? preferencesStore;
  final GranaPaCaApiClient? apiClient;
  final EncryptedCacheStore? encryptedCache;
  final AppLockController? appLock;
  final bool simulateNoConnections;
  final bool startInOnboarding;
  final bool startInServerAuth;
  final AppMode? initialMode;
  final String? initialServerUrl;
  final List<BankConnectionInfo>? initialConnections;
  final bool initialOffline;
  final DateTime? initialLastSyncedAt;

  @override
  State<GranaPaCaApp> createState() => _GranaPaCaAppState();
}

class _GranaPaCaAppState extends State<GranaPaCaApp>
    with WidgetsBindingObserver {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = AppState(
      dataset: widget.dataset,
      preferencesStore: widget.preferencesStore,
      apiClient: widget.apiClient,
      encryptedCache: widget.encryptedCache,
      appLock: widget.appLock,
      simulateNoConnections: widget.simulateNoConnections,
      initialMode: widget.initialMode,
      initialServerUrl: widget.initialServerUrl,
      initialConnections: widget.initialConnections,
      initialOffline: widget.initialOffline,
      initialLastSyncedAt: widget.initialLastSyncedAt,
    );
    unawaited(_state.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state.appLock.handleLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  Widget _resolveHome() {
    if (_state.appLock.isLocked) {
      return AppLockScreen(controller: _state.appLock);
    }
    if (_state.isRestoringOfflineCache) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.startInServerAuth ||
        (_state.isServerMode &&
            !_state.isAuthenticated &&
            !_state.isOffline)) {
      return ServerAuthScreen(initialServerUrl: _state.serverUrl);
    }
    if (widget.startInOnboarding) {
      return const OnboardingScreen(profileOnly: false);
    }
    return const AppShell();
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
          home: _resolveHome(),
        ),
      ),
    );
  }
}
