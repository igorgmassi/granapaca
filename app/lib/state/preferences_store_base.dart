import 'package:material_ui/material_ui.dart';

/// Persisted non-secret metadata for local App Lock (RF-04).
///
/// Stores ONLY the salted PBKDF2 hash (`salt:hash`), never the plaintext PIN.
class AppLockConfig {
  const AppLockConfig({
    required this.isEnabled,
    this.pinHash,
    this.biometricEnabled = false,
    this.inactivityTimeoutSeconds = 120,
  });

  final bool isEnabled;
  final String? pinHash;
  final bool biometricEnabled;
  final int inactivityTimeoutSeconds;

  factory AppLockConfig.fromJson(Map<String, dynamic> json) => AppLockConfig(
    isEnabled: (json['isEnabled'] as bool?) ?? false,
    pinHash: json['pinHash'] as String?,
    biometricEnabled: (json['biometricEnabled'] as bool?) ?? false,
    inactivityTimeoutSeconds:
        (json['inactivityTimeoutSeconds'] as num?)?.toInt() ?? 120,
  );

  Map<String, dynamic> toJson() => {
    'isEnabled': isEnabled,
    'pinHash': pinHash,
    'biometricEnabled': biometricEnabled,
    'inactivityTimeoutSeconds': inactivityTimeoutSeconds,
  };
}

/// Persistence contract for lightweight UI preferences (RF-01, RF-04, RF-05).
abstract class PreferencesStore {
  bool readHideValues();
  Future<void> writeHideValues(bool value);

  ThemeMode readThemeMode();
  Future<void> writeThemeMode(ThemeMode mode);

  String? readServerUrl();
  Future<void> writeServerUrl(String? url);

  AppLockConfig? readAppLockConfig();
  Future<void> writeAppLockConfig(AppLockConfig? config);

  bool readHasActiveServerProfile();
  Future<void> writeHasActiveServerProfile(bool value);
}

/// In-memory store used on web and for deterministic restart tests.
class InMemoryPreferencesStore implements PreferencesStore {
  InMemoryPreferencesStore({
    this._hideValues = false,
    this._themeMode = ThemeMode.system,
    this._serverUrl,
    this._appLockConfig,
    this._hasActiveServerProfile = false,
  });

  bool _hideValues;
  ThemeMode _themeMode;
  String? _serverUrl;
  AppLockConfig? _appLockConfig;
  bool _hasActiveServerProfile;

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

  @override
  AppLockConfig? readAppLockConfig() => _appLockConfig;

  @override
  Future<void> writeAppLockConfig(AppLockConfig? config) async {
    _appLockConfig = config;
  }

  @override
  bool readHasActiveServerProfile() => _hasActiveServerProfile;

  @override
  Future<void> writeHasActiveServerProfile(bool value) async {
    _hasActiveServerProfile = value;
  }
}
