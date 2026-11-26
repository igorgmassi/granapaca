import 'cache_storage_base.dart';

/// Web/non-IO fallback storage without external dependencies.
CacheStorage createDefaultCacheStorage() => InMemoryCacheStorage();

/// Isolated key storage fallback for web/non-IO platforms.
CacheStorage createDefaultKeyStorage() => InMemoryCacheStorage();
