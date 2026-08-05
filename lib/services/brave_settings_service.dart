import 'package:shared_preferences/shared_preferences.dart';

import '../models/brave_settings.dart';
import 'llm_settings_service.dart';

class BraveSettingsService {
  static const String _prefsKey = 'brave_settings';
  static const String _legacyApiKey = 'brave_api_key';
  static const String _searchApiKey = 'brave_search_api_key';
  static const String _answersApiKey = 'brave_answers_api_key';

  final SharedPreferences _prefs;
  final SecureKeyValueStore _secureStorage;

  BraveSettingsService({
    required SharedPreferences prefs,
    SecureKeyValueStore? secureStorage,
  })  : _prefs = prefs,
        _secureStorage = secureStorage ?? const FlutterSecureStorageAdapter();

  Future<void> _migrateLegacyKey() async {
    final existing = await _secureStorage.read(key: _searchApiKey);
    if (existing != null && existing.isNotEmpty) return;
    final legacy = await _secureStorage.read(key: _legacyApiKey);
    if (legacy == null || legacy.isEmpty) return;
    await _secureStorage.write(key: _searchApiKey, value: legacy);
  }

  Future<BraveSettings> loadSettings() async {
    await _migrateLegacyKey();
    final jsonString = _prefs.getString(_prefsKey);
    final settings = jsonString != null
        ? BraveSettings.fromJsonString(jsonString)
        : BraveSettings.defaults;
    final searchKey = await hasSearchApiKey;
    final answersKey = await hasAnswersApiKey;
    return settings.copyWith(
      searchKeyConfigured: searchKey,
      answersKeyConfigured: answersKey,
    );
  }

  Future<void> saveSettings(BraveSettings settings) async {
    await _prefs.setString(_prefsKey, settings.clamped().toJsonString());
  }

  Future<void> saveSearchApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _searchApiKey);
      return;
    }
    await _secureStorage.write(key: _searchApiKey, value: trimmed);
  }

  Future<void> clearSearchApiKey() async {
    await _secureStorage.delete(key: _searchApiKey);
  }

  Future<bool> get hasSearchApiKey async {
    final value = await _secureStorage.read(key: _searchApiKey);
    return value != null && value.isNotEmpty;
  }

  Future<String?> loadSearchApiKey() =>
      _secureStorage.read(key: _searchApiKey);

  Future<void> saveAnswersApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _answersApiKey);
      return;
    }
    await _secureStorage.write(key: _answersApiKey, value: trimmed);
  }

  Future<void> clearAnswersApiKey() async {
    await _secureStorage.delete(key: _answersApiKey);
  }

  Future<bool> get hasAnswersApiKey async {
    final value = await _secureStorage.read(key: _answersApiKey);
    return value != null && value.isNotEmpty;
  }

  Future<String?> loadAnswersApiKey() =>
      _secureStorage.read(key: _answersApiKey);

  // ---------------------------------------------------------------------------
  // Legacy API — kept for callers that haven't migrated yet
  // ---------------------------------------------------------------------------

  Future<void> saveApiKey(String apiKey) => saveSearchApiKey(apiKey);

  Future<void> clearApiKey() => clearSearchApiKey();

  Future<bool> get hasApiKey => hasSearchApiKey;

  Future<String?> loadApiKey() => loadSearchApiKey();
}
