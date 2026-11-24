import 'package:material_ui/material_ui.dart';

/// Persistence contract for lightweight UI preferences (RF-05).
abstract class PreferencesStore {
  bool readHideValues();
  Future<void> writeHideValues(bool value);

  ThemeMode readThemeMode();
  Future<void> writeThemeMode(ThemeMode mode);
}

/// In-memory store used on web and for deterministic restart tests.
class InMemoryPreferencesStore implements PreferencesStore {
  InMemoryPreferencesStore({
    this._hideValues = false,
    this._themeMode = ThemeMode.system,
  });

  bool _hideValues;
  ThemeMode _themeMode;

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
}
