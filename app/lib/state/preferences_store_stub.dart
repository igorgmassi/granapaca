import 'preferences_store_base.dart';

/// Web/non-IO fallback store without external dependencies.
PreferencesStore createDefaultPreferencesStore() => InMemoryPreferencesStore();
