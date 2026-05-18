import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/brave_settings.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:grepink/services/brave_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_secure_storage.dart';

void main() {
  group('BraveSettingsService', () {
    late SharedPreferences prefs;
    late FakeSecureStorage secureStorage;
    late BraveSettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStorage = FakeSecureStorage();
      service = BraveSettingsService(
        prefs: prefs,
        secureStorage: secureStorage,
      );
    });

    test('loads default settings when nothing is persisted', () async {
      final settings = await service.loadSettings();

      expect(settings.enabled, isFalse);
      expect(settings.resultCount, 5);
      expect(settings.safeSearch, BraveSafeSearch.moderate);
      expect(settings.apiKeyConfigured, isFalse);
    });

    test('persists non-sensitive config in SharedPreferences', () async {
      await service.saveSettings(
        const BraveSettings(
          enabled: true,
          resultCount: 7,
          safeSearch: BraveSafeSearch.strict,
        ),
      );

      final rawJson = prefs.getString('brave_settings') ?? '';
      expect(rawJson.contains('"enabled":true'), isTrue);
      expect(rawJson.contains('"resultCount":7'), isTrue);
      expect(rawJson.contains('strict'), isTrue);
      expect(rawJson.toLowerCase().contains('key'), isFalse);
    });

    test('stores the Brave API key in secure storage only', () async {
      await service.saveApiKey('brave-secret');

      expect(secureStorage.data['brave_api_key'], 'brave-secret');
      for (final key in prefs.getKeys()) {
        final value = prefs.get(key)?.toString() ?? '';
        expect(value.contains('brave-secret'), isFalse);
      }
    });

    test('clearing the key removes it from secure storage', () async {
      await service.saveApiKey('brave-secret');
      expect(await service.hasApiKey, isTrue);

      await service.clearApiKey();

      expect(await service.hasApiKey, isFalse);
      expect(secureStorage.data.containsKey('brave_api_key'), isFalse);
    });

    test('loadSettings derives apiKeyConfigured from secure storage', () async {
      await service.saveSettings(
        const BraveSettings(enabled: true, resultCount: 9),
      );
      await service.saveApiKey('brave-secret');

      final settings = await service.loadSettings();

      expect(settings.enabled, isTrue);
      expect(settings.resultCount, 9);
      expect(settings.apiKeyConfigured, isTrue);
    });
  });
}
