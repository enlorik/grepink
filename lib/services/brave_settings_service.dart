import 'package:shared_preferences/shared_preferences.dart';

import '../models/brave_settings.dart';
import 'llm_settings_service.dart';

class BraveSettingsService {
  static const String _prefsKey = 'brave_settings';
  static const String _secureApiKey = 'brave_api_key';

  final SharedPreferences _prefs;
  final SecureKeyValueStore _secureStorage;

  BraveSettingsService({
    required SharedPreferences prefs,
    SecureKeyValueStore? secureStorage,
  })  : _prefs = prefs,
        _secureStorage = secureStorage ?? const FlutterSecureStorageAdapter();

  Future<BraveSettings> loadSettings() async {
    final jsonString = _prefs.getString(_prefsKey);
    final settings = jsonString != null
        ? BraveSettings.fromJsonString(jsonString)
        : BraveSettings.defaults;
    final hasKey = await hasApiKey;
    return settings.copyWith(apiKeyConfigured: hasKey);
  }

  Future<void> saveSettings(BraveSettings settings) async {
    await _prefs.setString(_prefsKey, settings.clamped().toJsonString());
  }

  Future<void> saveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _secureApiKey);
      return;
    }

    await _secureStorage.write(key: _secureApiKey, value: trimmed);
  }

  Future<void> clearApiKey() async {
    await _secureStorage.delete(key: _secureApiKey);
  }

  Future<bool> get hasApiKey async {
    final value = await _secureStorage.read(key: _secureApiKey);
    return value != null && value.isNotEmpty;
  }

  Future<String?> loadApiKey() => _secureStorage.read(key: _secureApiKey);
}
