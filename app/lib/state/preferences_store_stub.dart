import 'preferences_store_base.dart';

/// Non-IO, non-web fallback store without external dependencies.
PreferencesStore createDefaultPreferencesStore() => InMemoryPreferencesStore();
