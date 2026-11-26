import 'dart:convert';
import 'dart:js_interop';

import 'package:material_ui/material_ui.dart';

import 'preferences_store_base.dart';

@JS('window.localStorage.getItem')
external String? _getItem(String key);

@JS('window.localStorage.setItem')
external void _setItem(String key, String value);

/// Browser localStorage-backed preferences store using dart:js_interop.
class WebPreferencesStore implements PreferencesStore {
  WebPreferencesStore() {
    _load();
  }

  static const _storageKey = 'granapaca.preferences.v1';

  bool _hideValues = false;
  ThemeMode _themeMode = ThemeMode.system;
  String? _serverUrl;
  AppLockConfig? _appLockConfig;
  bool _hasActiveServerProfile = false;

  void _load() {
    try {
      final raw = _getItem(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
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
      final url = decoded['serverUrl'];
      if (url is String && url.trim().isNotEmpty) {
        _serverUrl = url.trim();
      }
      final lockJson = decoded['appLockConfig'];
      if (lockJson is Map<String, dynamic>) {
        _appLockConfig = AppLockConfig.fromJson(lockJson);
      }
      final activeServer = decoded['hasActiveServerProfile'];
      if (activeServer is bool) {
        _hasActiveServerProfile = activeServer;
      }
    } catch (_) {
      // Ignore storage read failures in private mode or non-browser runtimes.
    }
  }

  void _save() {
    try {
      _setItem(
        _storageKey,
        jsonEncode({
          'hideValues': _hideValues,
          'themeMode': _themeMode.name,
          'serverUrl': _serverUrl,
          'appLockConfig': _appLockConfig?.toJson(),
          'hasActiveServerProfile': _hasActiveServerProfile,
        }),
      );
    } catch (_) {
      // Ignore storage write failures in private mode or non-browser runtimes.
    }
  }

  @override
  bool readHideValues() => _hideValues;

  @override
  Future<void> writeHideValues(bool value) async {
    _hideValues = value;
    _save();
  }

  @override
  ThemeMode readThemeMode() => _themeMode;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _save();
  }

  @override
  String? readServerUrl() => _serverUrl;

  @override
  Future<void> writeServerUrl(String? url) async {
    _serverUrl = (url == null || url.trim().isEmpty) ? null : url.trim();
    _save();
  }

  @override
  AppLockConfig? readAppLockConfig() => _appLockConfig;

  @override
  Future<void> writeAppLockConfig(AppLockConfig? config) async {
    _appLockConfig = config;
    _save();
  }

  @override
  bool readHasActiveServerProfile() => _hasActiveServerProfile;

  @override
  Future<void> writeHasActiveServerProfile(bool value) async {
    _hasActiveServerProfile = value;
    _save();
  }
}

PreferencesStore createDefaultPreferencesStore() => WebPreferencesStore();
