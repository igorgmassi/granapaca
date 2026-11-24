import 'package:material_ui/material_ui.dart';

/// Persistence contract for lightweight UI preferences (RF-01, RF-05).
abstract class PreferencesStore {
  bool readHideValues();
  Future<void> writeHideValues(bool value);

  ThemeMode readThemeMode();
  Future<void> writeThemeMode(ThemeMode mode);

  String? readServerUrl();
  Future<void> writeServerUrl(String? url);
}

/// In-memory store used on web and for deterministic restart tests.
class InMemoryPreferencesStore implements PreferencesStore {
  InMemoryPreferencesStore({
    this._hideValues = false,
    this._themeMode = ThemeMode.system,
    this._serverUrl,
  });

  bool _hideValues;
  ThemeMode _themeMode;
  String? _serverUrl;

  @override
  bool readHideValues() => _hideValues;

  @override
  Future<void> writeHideValues(bool value) async {
    _hideValues = value;
  }

  @override
  ThemeMode readThemeMode() => _themeMode;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {
    _themeMode = mode;
  }

  @override
  String? readServerUrl() => _serverUrl;

  @override
  Future<void> writeServerUrl(String? url) async {
    _serverUrl = url;
  }
}
