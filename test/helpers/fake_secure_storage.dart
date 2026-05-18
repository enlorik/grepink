import 'package:grepink/services/llm_settings_service.dart';

class FakeSecureStorage implements SecureKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({required String key}) async => _data[key];

  @override
  Future<void> delete({required String key}) async => _data.remove(key);

  Map<String, String> get data => Map<String, String>.unmodifiable(_data);
}
