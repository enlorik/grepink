import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class RailwaySettingsStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}

class _SecureSettingsStorage implements RailwaySettingsStorage {
  static const _storage = FlutterSecureStorage();
  static const _keyToken = 'railway_sync_token';

  @override
  Future<String?> readToken() => _storage.read(key: _keyToken);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _keyToken, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _keyToken);
}

class RailwaySettingsService {
  static const _keyApiUrl = 'railway_sync_api_url';
  static const _keyLastSyncedAt = 'railway_sync_last_synced_at';

  final RailwaySettingsStorage _storage;

  RailwaySettingsService({RailwaySettingsStorage? storage})
      : _storage = storage ?? _SecureSettingsStorage();

  Future<String?> getApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiUrl);
  }

  Future<void> setApiUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiUrl, url);
  }

  Future<String?> getToken() => _storage.readToken();

  Future<void> setToken(String token) => _storage.writeToken(token);

  Future<void> clearConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyApiUrl);
    await prefs.remove(_keyLastSyncedAt);
    await _storage.deleteToken();
  }

  Future<DateTime?> getLastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLastSyncedAt);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastSyncedAt(DateTime dt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncedAt, dt.millisecondsSinceEpoch);
  }

  Future<bool> isConfigured() async {
    final url = await getApiUrl();
    final token = await getToken();
    return url != null && url.isNotEmpty && token != null && token.isNotEmpty;
  }
}
