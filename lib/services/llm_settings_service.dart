import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm_provider_config.dart';

// ---------------------------------------------------------------------------
// Secure storage abstraction (injectable for tests)
// ---------------------------------------------------------------------------

/// Minimal interface for key/value secure storage so tests can inject a fake
/// without requiring native platform channels.
abstract class SecureKeyValueStore {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

/// Production adapter wrapping [FlutterSecureStorage].
class FlutterSecureStorageAdapter implements SecureKeyValueStore {
  const FlutterSecureStorageAdapter([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

// ---------------------------------------------------------------------------
// LlmSettingsService
// ---------------------------------------------------------------------------

/// Persists non-sensitive LLM configuration in [SharedPreferences] and the
/// API key (sensitive) in [SecureKeyValueStore] (FlutterSecureStorage in
/// production, an in-memory fake in tests).
///
/// The raw API key is never written to [SharedPreferences].
class LlmSettingsService {
  static const String _kPrefsKey = 'llm_provider_config';
  static const String _kSecureApiKey = 'llm_api_key';

  final SharedPreferences _prefs;
  final SecureKeyValueStore _secureStorage;

  LlmSettingsService({
    required SharedPreferences prefs,
    SecureKeyValueStore? secureStorage,
  })  : _prefs = prefs,
        _secureStorage =
            secureStorage ?? const FlutterSecureStorageAdapter();

  // -------------------------------------------------------------------------
  // Config (non-sensitive)
  // -------------------------------------------------------------------------

  /// Loads the persisted [LlmProviderConfig].  Returns [LlmProviderConfig.defaults]
  /// when nothing has been saved yet.
  ///
  /// [apiKeyConfigured] is set by checking whether the secure store has a key,
  /// so that the returned config accurately reflects the current state without
  /// exposing the key value.
  Future<LlmProviderConfig> loadConfig() async {
    final jsonString = _prefs.getString(_kPrefsKey);
    final config = jsonString != null
        ? LlmProviderConfig.fromJsonString(jsonString)
        : LlmProviderConfig.defaults;
    final hasKey = await hasApiKey;
    return config.copyWith(apiKeyConfigured: hasKey);
  }

  /// Saves [config] to [SharedPreferences].
  ///
  /// [apiKeyConfigured] is intentionally stripped from the persisted JSON to
  /// keep it derived at load-time from the secure store.
  Future<void> saveConfig(LlmProviderConfig config) async {
    await _prefs.setString(_kPrefsKey, config.toJsonString());
  }

  // -------------------------------------------------------------------------
  // API key (sensitive)
  // -------------------------------------------------------------------------

  /// Stores the API key in [SecureKeyValueStore].  Passing an empty string
  /// removes the key (same as [clearApiKey]).
  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _kSecureApiKey);
    } else {
      await _secureStorage.write(key: _kSecureApiKey, value: trimmed);
    }
  }

  /// Removes the API key from [SecureKeyValueStore].
  Future<void> clearApiKey() async {
    await _secureStorage.delete(key: _kSecureApiKey);
  }

  /// Returns `true` when a non-empty API key is present in the secure store.
  /// Does **not** return the key value.
  Future<bool> get hasApiKey async {
    final value = await _secureStorage.read(key: _kSecureApiKey);
    return value != null && value.isNotEmpty;
  }

  /// Reads the API key from secure storage for provider construction.
  /// Returns `null` when no key has been stored.
  ///
  /// Callers should pass this to [LlmProviderFactory] and not persist it
  /// anywhere unencrypted.
  Future<String?> loadApiKey() => _secureStorage.read(key: _kSecureApiKey);
}
