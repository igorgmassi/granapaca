import 'dart:typed_data';

/// Platform-neutral binary key-value storage abstraction for encrypted local
/// cache files (RF-21).
abstract class CacheStorage {
  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List data);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// In-memory cache storage used in tests and Web demo mode.
class InMemoryCacheStorage implements CacheStorage {
  final Map<String, Uint8List> _entries = {};

  Map<String, Uint8List> get entries => Map.unmodifiable(_entries);

  @override
  Future<Uint8List?> readBytes(String key) async {
    final data = _entries[key];
    return data == null ? null : Uint8List.fromList(data);
  }

  @override
  Future<void> writeBytes(String key, Uint8List data) async {
    _entries[key] = Uint8List.fromList(data);
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _entries.clear();
  }
}
