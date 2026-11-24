import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'preferences_store_base.dart';

/// File-backed preferences store for desktop and mobile platforms.
class FilePreferencesStore implements PreferencesStore {
  FilePreferencesStore(this.file) {
    _load();
  }

  final File file;
  bool _hideValues = false;
  ThemeMode _themeMode = ThemeMode.system;

  void _load() {
    try {
      if (!file.existsSync()) return;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return;
      final hide = decoded['hideValues'];
      if (hide is bool) _hideValues = hide;
      final theme = decoded['themeMode'];
      if (theme is String) {
        for (final m in ThemeMode.values) {
          if (m.name == theme) {
            _themeMode = m;
            break;
          }
        }
      }
    } catch (_) {
      // Ignore corrupt or unreadable local preference files safely.
    }
  }

  Future<void> _save() async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'hideValues': _hideValues, 'themeMode': _themeMode.name}),
      );
    } catch (_) {
      // Ignore write failures on restricted sandboxes.
    }
  }

  @override
  bool readHideValues() => _hideValues;

  @override
  Future<void> writeHideValues(bool value) async {
    _hideValues = value;
    await _save();
  }

  @override
  ThemeMode readThemeMode() => _themeMode;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _save();
  }
}

PreferencesStore createDefaultPreferencesStore() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return InMemoryPreferencesStore();
  }
  final baseDir =
      Platform.environment['XDG_CONFIG_HOME'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;
  return FilePreferencesStore(File('$baseDir/.granapaca/preferences.json'));
}
