import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../state/preferences_store_base.dart';
import '../storage/pure_crypto.dart';

/// Outcome of an OS biometric unlock prompt.
enum BiometricAuthResult { authenticated, cancelled, unavailable, failed }

/// Injectable biometric verification contract so native OS authenticators and
/// deterministic tests share the exact same interface without third-party
/// native plugins (RF-04).
abstract class BiometricAuthenticator {
  Future<bool> isAvailable();

  Future<BiometricAuthResult> authenticate({required String localizedReason});
}

/// Safe cross-platform default when device biometrics are unavailable.
class UnavailableBiometricAuthenticator implements BiometricAuthenticator {
  const UnavailableBiometricAuthenticator();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<BiometricAuthResult> authenticate({
    required String localizedReason,
  }) async => BiometricAuthResult.unavailable;
}

/// Manages local app lock state: 6-digit PIN (stored ONLY as salted
/// PBKDF2-HMAC-SHA256 hash), optional biometric hook with automatic fallback
/// to PIN, inactivity timeout (default 2 minutes per RNF-10), and 5-attempt
/// lockout that clears the active session (RF-04).
class AppLockController extends ChangeNotifier {
  AppLockController({
    BiometricAuthenticator? biometricAuthenticator,
    this._preferencesStore,
    DateTime Function()? clock,
    this.onLockoutSessionCleared,
    this.onPinConfigured,
    this.onPinUnlocked,
    this.onBiometricUnlocked,
    this.onLockDisabled,
    this.onLocked,
    this._inactivityTimeout = defaultInactivityTimeout,
    this._hashIterations = defaultHashIterations,
  }) : _biometricAuthenticator =
           biometricAuthenticator ?? const UnavailableBiometricAuthenticator(),
       _clock = clock ?? DateTime.now {
    if (_preferencesStore != null) {
      _loadFromPreferences(_preferencesStore!);
    }
  }

  static const int pinLength = 6;
  static const int maxFailedAttempts = 5;
  static const Duration defaultInactivityTimeout = Duration(minutes: 2);
  static const int defaultHashIterations = 5000;

  final BiometricAuthenticator _biometricAuthenticator;
  PreferencesStore? _preferencesStore;
  final DateTime Function() _clock;
  final int _hashIterations;

  /// Invoked immediately after [maxFailedAttempts] consecutive wrong PINs so
  /// [AppState] clears the session and forces full re-login (RF-04).
  VoidCallback? onLockoutSessionCleared;

  /// Invoked when the user sets a new PIN so the encrypted cache can wrap its
  /// DEK with a PBKDF2-derived KEK.
  void Function(String pin)? onPinConfigured;

  /// Invoked when the user unlocks with a valid PIN so the encrypted cache can
  /// unwrap its DEK and restore offline data.
  void Function(String pin)? onPinUnlocked;

  /// Invoked after successful OS biometric unlock.
  VoidCallback? onBiometricUnlocked;

  /// Invoked when app lock is disabled.
  VoidCallback? onLockDisabled;

  /// Invoked whenever the controller transitions into the locked state.
  VoidCallback? onLocked;

  bool _isEnabled = false;
  bool _isLocked = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _lockedOut = false;
  Duration _inactivityTimeout;
  String? _pinHash;
  int _failedAttempts = 0;
  DateTime? _backgroundedAt;

  bool get isEnabled => _isEnabled;
  bool get isLocked => _isLocked;
  bool get hasPin => _pinHash != null && _pinHash!.isNotEmpty;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricAvailable => _biometricAvailable;
  bool get canUseBiometrics => _biometricEnabled && _biometricAvailable;
  bool get lockedOut => _lockedOut;
  Duration get inactivityTimeout => _inactivityTimeout;
  int get hashIterations => _hashIterations;
  int get failedAttempts => _failedAttempts;
  int get remainingAttempts =>
      (maxFailedAttempts - _failedAttempts).clamp(0, maxFailedAttempts);

  /// Exposed for security audits/tests verifying that only `salt:hash` is ever
  /// held in memory or persisted — never the plaintext PIN.
  String? get storedPinHash => _pinHash;

  /// Attaches a [PreferencesStore] after construction (if not already bound)
  /// and restores any persisted lock configuration on cold start.
  void attachPreferencesStore(PreferencesStore store) {
    if (_preferencesStore != null) return;
    _preferencesStore = store;
    if (!_isEnabled && !hasPin) {
      _loadFromPreferences(store);
    }
  }

  void _loadFromPreferences(PreferencesStore store) {
    final saved = store.readAppLockConfig();
    if (saved == null ||
        !saved.isEnabled ||
        saved.pinHash == null ||
        saved.pinHash!.isEmpty) {
      return;
    }
    _isEnabled = true;
    _pinHash = saved.pinHash;
    _biometricEnabled = saved.biometricEnabled;
    if (saved.inactivityTimeoutSeconds > 0) {
      _inactivityTimeout = Duration(seconds: saved.inactivityTimeoutSeconds);
    }
    _isLocked = true;
  }

  void _persistConfig() {
    final store = _preferencesStore;
    if (store == null) return;
    if (_isEnabled && hasPin) {
      unawaited(
        store.writeAppLockConfig(
          AppLockConfig(
            isEnabled: true,
            pinHash: _pinHash,
            biometricEnabled: _biometricEnabled,
            inactivityTimeoutSeconds: _inactivityTimeout.inSeconds,
          ),
        ),
      );
    } else {
      unawaited(store.writeAppLockConfig(null));
    }
  }

  /// Checks biometric hardware capability and locks on cold start if enabled.
  Future<void> initialize() async {
    try {
      _biometricAvailable = await _biometricAuthenticator.isAvailable();
    } catch (_) {
      _biometricAvailable = false;
    }
    if (_isEnabled && hasPin) {
      _isLocked = true;
    }
    notifyListeners();
  }

  /// Validates and configures a 6-digit PIN hashed with a fresh random salt.
  Future<void> configurePin(
    String pin, {
    bool enableBiometric = false,
  }) async {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('O PIN precisa ter exatamente $pinLength dígitos.');
    }
    try {
      _biometricAvailable = await _biometricAuthenticator.isAvailable();
    } catch (_) {
      _biometricAvailable = false;
    }
    _pinHash = _hashPin(pin);
    _isEnabled = true;
    _biometricEnabled = enableBiometric && _biometricAvailable;
    _failedAttempts = 0;
    _lockedOut = false;
    _isLocked = false;
    _backgroundedAt = null;
    _persistConfig();
    onPinConfigured?.call(pin);
    notifyListeners();
  }

  /// Disables app lock and clears stored PIN hash.
  void disableLock() {
    _isEnabled = false;
    _isLocked = false;
    _biometricEnabled = false;
    _pinHash = null;
    _failedAttempts = 0;
    _lockedOut = false;
    _backgroundedAt = null;
    _persistConfig();
    onLockDisabled?.call();
    notifyListeners();
  }

  void setInactivityTimeout(Duration timeout) {
    if (timeout <= Duration.zero) return;
    _inactivityTimeout = timeout;
    _persistConfig();
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      _biometricAvailable = await _biometricAuthenticator.isAvailable();
    } catch (_) {
      _biometricAvailable = false;
    }
    _biometricEnabled = enabled && _biometricAvailable;
    _persistConfig();
    notifyListeners();
  }

  void lockNow() {
    if (!_isEnabled || !hasPin) return;
    _isLocked = true;
    _lockedOut = false;
    onLocked?.call();
    notifyListeners();
  }

  void clearLockoutNotice() {
    if (!_lockedOut) return;
    _lockedOut = false;
    notifyListeners();
  }

  /// Tracks background/foreground transitions to lock automatically once
  /// [inactivityTimeout] has elapsed (RNF-10, RF-04).
  void handleLifecycleState(AppLifecycleState state) {
    if (!_isEnabled || !hasPin) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= _clock();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && _clock().difference(since) >= _inactivityTimeout) {
          _isLocked = true;
          onLocked?.call();
          notifyListeners();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Attempts to unlock with [pin]. After [maxFailedAttempts] consecutive
  /// failures, clears the session via [onLockoutSessionCleared] and resets the
  /// lock so the user must authenticate again from scratch (RF-04).
  bool verifyPin(String pin) {
    final stored = _pinHash;
    if (stored == null || !isValidPinFormat(pin)) {
      return false;
    }

    if (_matchesHash(pin, stored)) {
      _failedAttempts = 0;
      _isLocked = false;
      _lockedOut = false;
      onPinUnlocked?.call(pin);
      notifyListeners();
      return true;
    }

    _failedAttempts++;
    if (_failedAttempts >= maxFailedAttempts) {
      _lockedOut = true;
      _isLocked = false;
      _isEnabled = false;
      _biometricEnabled = false;
      _pinHash = null;
      _failedAttempts = 0;
      _backgroundedAt = null;
      _persistConfig();
      onLockoutSessionCleared?.call();
      notifyListeners();
      return false;
    }

    notifyListeners();
    return false;
  }

  /// Attempts biometric unlock; any non-success outcome leaves the screen
  /// locked so the user falls back smoothly to PIN entry.
  Future<BiometricAuthResult> tryBiometricUnlock() async {
    if (!_isLocked) return BiometricAuthResult.authenticated;
    try {
      _biometricAvailable = await _biometricAuthenticator.isAvailable();
    } catch (_) {
      _biometricAvailable = false;
    }
    if (!_biometricEnabled || !_biometricAvailable) {
      notifyListeners();
      return BiometricAuthResult.unavailable;
    }
    final result = await _biometricAuthenticator.authenticate(
      localizedReason: 'Desbloqueie o GranaPaCá para acessar suas finanças',
    );
    if (result == BiometricAuthResult.authenticated) {
      _failedAttempts = 0;
      _isLocked = false;
      _lockedOut = false;
      onBiometricUnlocked?.call();
      notifyListeners();
    }
    return result;
  }

  static bool isValidPinFormat(String pin) =>
      pin.length == pinLength && RegExp(r'^\d{6}$').hasMatch(pin);

  String _hashPin(String pin) {
    final salt = PureCrypto.randomBytes(16);
    final derived = PureCrypto.pbkdf2Sha256(
      password: Uint8List.fromList(utf8.encode(pin)),
      salt: salt,
      iterations: _hashIterations,
    );
    return '${base64Encode(salt)}:${base64Encode(derived)}';
  }

  bool _matchesHash(String pin, String encoded) {
    final parts = encoded.split(':');
    if (parts.length != 2) return false;
    try {
      final salt = base64Decode(parts[0]);
      final expected = base64Decode(parts[1]);
      final computed = PureCrypto.pbkdf2Sha256(
        password: Uint8List.fromList(utf8.encode(pin)),
        salt: Uint8List.fromList(salt),
        iterations: _hashIterations,
      );
      return PureCrypto.constantTimeEquals(
        computed,
        Uint8List.fromList(expected),
      );
    } catch (_) {
      return false;
    }
  }
}
