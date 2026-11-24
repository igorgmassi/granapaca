import 'dart:io';
import 'dart:typed_data';

import 'cache_storage_base.dart';

/// File-backed binary cache storage for mobile and desktop platforms.
class FileCacheStorage implements CacheStorage {
  FileCacheStorage(this.directory);

  final Directory directory;

  File _fileFor(String key) {
    final sanitized = key.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return File('${directory.path}/$sanitized');
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
    final file = _fileFor(key);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(file.path);
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

CacheStorage createDefaultCacheStorage() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return InMemoryCacheStorage();
  }
  final baseDir =
      Platform.environment['XDG_CACHE_HOME'] ??
      Platform.environment['XDG_CONFIG_HOME'] ??
      Platform.environment['HOME'] ??
      Directory.systemTemp.path;
  return FileCacheStorage(Directory('$baseDir/.granapaca/cache'));
}
