import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/brave_settings.dart';
import 'package:grepink/providers/brave_settings_provider.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:grepink/services/brave_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<(BraveSettingsService, FakeSecureStorage)> _makeService() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = FakeSecureStorage();
  final service = BraveSettingsService(prefs: prefs, secureStorage: secure);
  return (service, secure);
}

Future<(ProviderContainer, BraveSettingsService, FakeSecureStorage, SharedPreferences)>
    _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secure = FakeSecureStorage();
  final service = BraveSettingsService(prefs: prefs, secureStorage: secure);
  final container = ProviderContainer(
    overrides: [braveSettingsServiceProvider.overrideWith((_) async => service)],
  );
  return (container, service, secure, prefs);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BraveSettings model — serialisation safety', () {
    test('toJson() contains only the expected non-sensitive fields', () {
      const settings = BraveSettings(
        enabled: true,
        resultCount: 7,
        safeSearch: BraveSafeSearch.strict,
        apiKeyConfigured: true,
      );

      final json = settings.toJson();

      expect(json.containsKey('enabled'), isTrue);
      expect(json.containsKey('resultCount'), isTrue);
      expect(json.containsKey('safeSearch'), isTrue);
      expect(json.containsKey('apiKeyConfigured'), isFalse,
          reason: 'apiKeyConfigured must not be serialised to JSON');
      expect(json.containsKey('apiKey'), isFalse);
      expect(json.containsKey('api_key'), isFalse);
    });

    test('toJsonString() does not contain API key related terms', () {
      const settings = BraveSettings(
        enabled: true,
        resultCount: 3,
        apiKeyConfigured: true,
      );

      final jsonString = settings.toJsonString();

      expect(jsonString.toLowerCase().contains('apikey'), isFalse);
      expect(jsonString.toLowerCase().contains('api_key'), isFalse);
      expect(jsonString.toLowerCase().contains('configured'), isFalse,
          reason: 'apiKeyConfigured flag must not leak into stored JSON');
    });

    test('round-trip through toJsonString/fromJsonString never restores apiKeyConfigured', () {
      const original = BraveSettings(
        enabled: true,
        resultCount: 10,
        safeSearch: BraveSafeSearch.strict,
        apiKeyConfigured: true,
      );

      final restored = BraveSettings.fromJsonString(original.toJsonString());

      expect(restored.apiKeyConfigured, isFalse,
          reason: 'apiKeyConfigured is not stored so it cannot be restored from JSON');
    });

    test('fromJsonString ignores an injected apiKey field without throwing', () {
      const injected =
          '{"enabled":true,"resultCount":5,"safeSearch":"moderate","apiKey":"sk-leaked"}';

      final settings = BraveSettings.fromJsonString(injected);

      expect(settings.enabled, isTrue);
      expect(settings.resultCount, 5);
      expect(settings.apiKeyConfigured, isFalse);
    });
  });

  group('BraveSettingsService — key safety', () {
    test('saveApiKey with empty string deletes the key from secure storage', () async {
      final (service, secure) = await _makeService();
      await service.saveApiKey('real-key');
      expect(secure.data.containsKey('brave_api_key'), isTrue);

      await service.saveApiKey('');

      expect(secure.data.containsKey('brave_api_key'), isFalse);
      expect(await service.hasApiKey, isFalse);
    });

    test('saveApiKey with whitespace-only string is treated as empty', () async {
      final (service, secure) = await _makeService();
      await service.saveApiKey('   ');

      expect(secure.data.containsKey('brave_api_key'), isFalse);
      expect(await service.hasApiKey, isFalse);
    });

    test('loadApiKey returns null after the key is cleared', () async {
      final (service, _) = await _makeService();
      await service.saveApiKey('real-key');
      await service.clearApiKey();

      final loaded = await service.loadApiKey();

      expect(loaded, isNull);
    });

    test('saveSettings never writes the API key value to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secure = FakeSecureStorage();
      final service = BraveSettingsService(prefs: prefs, secureStorage: secure);
      const settings = BraveSettings(enabled: true, resultCount: 5);
      await service.saveSettings(settings);

      for (final key in prefs.getKeys()) {
        final value = prefs.get(key)?.toString() ?? '';
        expect(value.toLowerCase().contains('apikey'), isFalse);
        expect(value.toLowerCase().contains('api_key'), isFalse);
      }
    });
  });

  group('BraveSettingsNotifier — key safety', () {
    test('clearing API key updates apiKeyConfigured to false', () async {
      final (container, _, _, _) = await _makeContainer();
      addTearDown(container.dispose);

      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).saveApiKey('brave-key');
      expect(
        container.read(braveSettingsProvider).valueOrNull!.apiKeyConfigured,
        isTrue,
      );

      await container.read(braveSettingsProvider.notifier).clearApiKey();

      expect(
        container.read(braveSettingsProvider).valueOrNull!.apiKeyConfigured,
        isFalse,
      );
    });

    test('empty API key is treated as no key — provider reads unconfigured', () async {
      final (container, _, secure, _) = await _makeContainer();
      addTearDown(container.dispose);

      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).saveApiKey('');

      expect(secure.data.containsKey('brave_api_key'), isFalse);
      expect(
        container.read(braveSettingsProvider).valueOrNull!.apiKeyConfigured,
        isFalse,
      );
    });

    test('persisted settings JSON never includes API key value', () async {
      final (container, _, _, prefs) = await _makeContainer();
      addTearDown(container.dispose);

      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).saveApiKey('my-api-key');
      await container.read(braveSettingsProvider.notifier).setEnabled(true);

      final raw = prefs.getString('brave_settings') ?? '';
      expect(raw.contains('my-api-key'), isFalse,
          reason: 'API key must never appear in SharedPreferences');
    });
  });

  group('BraveEvidenceProvider — empty key safety', () {
    test('returns empty list when API key is empty without making network calls',
        () async {
      final provider = BraveEvidenceProvider(apiKey: '');
      final results = await provider.fetch('What is photosynthesis?');
      expect(results, isEmpty);
    });

    test('returns empty list when API key is whitespace', () async {
      final provider = BraveEvidenceProvider(apiKey: '   ');
      final results = await provider.fetch('test question');
      expect(results, isEmpty);
    });
  });
}
