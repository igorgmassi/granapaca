import 'dart:io';
import 'dart:typed_data';

import 'cache_storage_base.dart';

/// File-backed binary cache storage for mobile and desktop platforms.
class FileCacheStorage implements CacheStorage {
  FileCacheStorage(this.directory, {this.restrictPermissions = false});

  final Directory directory;
  final bool restrictPermissions;

  File _fileFor(String key) {
    final sanitized = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${directory.path}/$sanitized');
  }

  Future<void> _chmodIfPosix(String mode, String path) async {
    if (!restrictPermissions || Platform.isWindows) return;
    try {
      await Process.run('chmod', [mode, path]);
    } catch (_) {
      // Best-effort POSIX permission hardening.
    }
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeBytes(String key, Uint8List data) async {
    await directory.create(recursive: true);
    await _chmodIfPosix('700', directory.path);
    final file = _fileFor(key);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await _chmodIfPosix('600', tmp.path);
    await tmp.rename(file.path);
    await _chmodIfPosix('600', file.path);
  }

  @override
  Future<void> delete(String key) async {
    final file = _fileFor(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteAll() async {
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) {
          await entity.delete();
        }
      }
    }
  }
}

String _resolveCacheBaseDir() =>
    Platform.environment['XDG_CACHE_HOME'] ??
    Platform.environment['LOCALAPPDATA'] ??
    Platform.environment['APPDATA'] ??
    Platform.environment['XDG_CONFIG_HOME'] ??
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    Directory.systemTemp.path;

String _resolveKeyBaseDir() =>
    Platform.environment['XDG_DATA_HOME'] ??
    Platform.environment['XDG_CONFIG_HOME'] ??
    Platform.environment['APPDATA'] ??
    Platform.environment['LOCALAPPDATA'] ??
    Platform.environment['HOME'] ??
    Platform.environment['USERPROFILE'] ??
    Directory.systemTemp.path;

CacheStorage createDefaultCacheStorage() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return InMemoryCacheStorage();
  }
  final baseDir = _resolveCacheBaseDir();
  return FileCacheStorage(Directory('$baseDir/.granapaca/cache'));
}

/// Separate key-material storage located outside the offline snapshot cache
/// directory, with restrictive POSIX permissions (0700/0600).
CacheStorage createDefaultKeyStorage() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return InMemoryCacheStorage();
  }
  final baseDir = _resolveKeyBaseDir();
  return FileCacheStorage(
    Directory('$baseDir/.granapaca/keystore'),
    restrictPermissions: true,
  );
}
