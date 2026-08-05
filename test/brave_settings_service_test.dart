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
      expect(settings.searchKeyConfigured, isFalse);
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

      expect(secureStorage.data['brave_search_api_key'], 'brave-secret');
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
      expect(secureStorage.data.containsKey('brave_search_api_key'), isFalse);
    });

    test('saving empty string clears the key (including legacy key)', () async {
      await secureStorage.write(key: 'brave_api_key', value: 'legacy-value');
      await service.loadSettings(); // trigger migration → brave_search_api_key set

      await service.saveSearchApiKey('');

      expect(secureStorage.data.containsKey('brave_search_api_key'), isFalse);
      expect(secureStorage.data.containsKey('brave_api_key'), isFalse,
          reason: 'legacy key must be removed to prevent re-migration after empty save');
    });

    group('legacy key migration', () {
      test('existing brave_api_key is copied to brave_search_api_key on first load',
          () async {
        await secureStorage.write(
            key: 'brave_api_key', value: 'legacy-key-value');

        final settings = await service.loadSettings();

        expect(settings.searchKeyConfigured, isTrue);
        expect(await service.loadSearchApiKey(), 'legacy-key-value');
      });

      test('brave_api_key is not deleted after migration', () async {
        await secureStorage.write(
            key: 'brave_api_key', value: 'legacy-key-value');

        await service.loadSettings();

        expect(secureStorage.data.containsKey('brave_api_key'), isTrue);
        expect(secureStorage.data['brave_api_key'], 'legacy-key-value');
      });

      test('clearSearchApiKey also removes the legacy key to prevent re-migration',
          () async {
        await secureStorage.write(
            key: 'brave_api_key', value: 'legacy-key-value');
        await service.loadSettings(); // trigger migration

        await service.clearSearchApiKey();

        expect(secureStorage.data.containsKey('brave_search_api_key'), isFalse);
        expect(secureStorage.data.containsKey('brave_api_key'), isFalse,
            reason: 'legacy key must be removed so next loadSettings does not re-populate it');
      });

      test('brave_answers_api_key is empty after legacy key migration', () async {
        await secureStorage.write(
            key: 'brave_api_key', value: 'legacy-key-value');

        final settings = await service.loadSettings();

        expect(await service.loadAnswersApiKey(), isNull);
        expect(settings.answersKeyConfigured, isFalse);
      });

      test('search and answers keys are stored independently', () async {
        await service.saveSearchApiKey('search-key-abc');
        await service.saveAnswersApiKey('answers-key-xyz');

        expect(await service.loadSearchApiKey(), 'search-key-abc');
        expect(await service.loadAnswersApiKey(), 'answers-key-xyz');
        expect(secureStorage.data['brave_search_api_key'], 'search-key-abc');
        expect(secureStorage.data['brave_answers_api_key'], 'answers-key-xyz');
        expect(
            secureStorage.data['brave_search_api_key'], isNot('answers-key-xyz'));
        expect(
            secureStorage.data['brave_answers_api_key'], isNot('search-key-abc'));
      });
    });

    test('loadSettings derives searchKeyConfigured from secure storage', () async {
      await service.saveSettings(
        const BraveSettings(enabled: true, resultCount: 9),
      );
      await service.saveApiKey('brave-secret');

      final settings = await service.loadSettings();

      expect(settings.enabled, isTrue);
      expect(settings.resultCount, 9);
      expect(settings.searchKeyConfigured, isTrue);
    });
  });
}
