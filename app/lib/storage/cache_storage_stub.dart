import 'cache_storage_base.dart';

/// Web/non-IO fallback storage without external dependencies.
CacheStorage createDefaultCacheStorage() => InMemoryCacheStorage();
