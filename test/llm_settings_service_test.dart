import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/llm_provider_config.dart';
import 'package:grepink/services/llm_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/fake_secure_storage.dart';

void main() {
  group('LlmSettingsService', () {
    late SharedPreferences prefs;
    late FakeSecureStorage secureStorage;
    late LlmSettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStorage = FakeSecureStorage();
      service = LlmSettingsService(
        prefs: prefs,
        secureStorage: secureStorage,
      );
    });

    // -----------------------------------------------------------------------
    // Default state
    // -----------------------------------------------------------------------
    group('initial state', () {
      test('loadConfig returns defaults when nothing is saved', () async {
        final config = await service.loadConfig();
        expect(config.providerKind, LlmProviderConfig.defaults.providerKind);
        expect(config.baseUrl, LlmProviderConfig.defaults.baseUrl);
        expect(config.model, LlmProviderConfig.defaults.model);
        expect(config.maxTokens, LlmProviderConfig.defaults.maxTokens);
        expect(config.temperature, LlmProviderConfig.defaults.temperature);
      });

      test('hasApiKey is false initially', () async {
        expect(await service.hasApiKey, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // Config persistence
    // -----------------------------------------------------------------------
    group('saveConfig / loadConfig', () {
      test('saves and loads non-sensitive config via SharedPreferences', () async {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'http://localhost:1234/v1',
          model: 'phi3',
          maxTokens: 512,
          temperature: 0.6,
        );

        await service.saveConfig(config);
        final loaded = await service.loadConfig();

        expect(loaded.providerKind, LlmProviderKind.openAICompatible);
        expect(loaded.baseUrl, 'http://localhost:1234/v1');
        expect(loaded.model, 'phi3');
        expect(loaded.maxTokens, 512);
        expect(loaded.temperature, 0.6);
      });

      test('API key is NOT stored in SharedPreferences', () async {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
          apiKeyConfigured: true,
        );

        await service.saveConfig(config);

        // Inspect raw SharedPreferences value directly
        final rawJson = prefs.getString('llm_provider_config') ?? '';
        expect(rawJson.contains('apiKey'), isFalse);
        expect(rawJson.toLowerCase().contains('sk-'), isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // API key persistence
    // -----------------------------------------------------------------------
    group('saveApiKey', () {
      test('stores API key in secure storage, not SharedPreferences', () async {
        await service.saveApiKey('sk-test-key');

        // Must be in secure storage
        expect(secureStorage.data.containsKey('llm_api_key'), isTrue);
        expect(secureStorage.data['llm_api_key'], 'sk-test-key');

        // Must NOT be in SharedPreferences
        for (final key in prefs.getKeys()) {
          final value = prefs.get(key)?.toString() ?? '';
          expect(value.contains('sk-test-key'), isFalse,
              reason: 'API key found in SharedPreferences under key "$key"');
        }
      });

      test('saving empty/blank key removes it from secure storage', () async {
        await service.saveApiKey('sk-test-key');
        expect(await service.hasApiKey, isTrue);

        await service.saveApiKey('');
        expect(await service.hasApiKey, isFalse);

        await service.saveApiKey('sk-test-key');
        await service.saveApiKey('   ');
        expect(await service.hasApiKey, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // clearApiKey
    // -----------------------------------------------------------------------
    group('clearApiKey', () {
      test('removes the API key from secure storage', () async {
        await service.saveApiKey('sk-to-clear');
        expect(await service.hasApiKey, isTrue);

        await service.clearApiKey();
        expect(await service.hasApiKey, isFalse);
      });

      test('clearApiKey is safe to call when no key is set', () async {
        await expectLater(service.clearApiKey(), completes);
      });
    });

    // -----------------------------------------------------------------------
    // hasApiKey
    // -----------------------------------------------------------------------
    group('hasApiKey', () {
      test('returns true after saving a non-empty key', () async {
        await service.saveApiKey('sk-abc');
        expect(await service.hasApiKey, isTrue);
      });

      test('returns false after clearing', () async {
        await service.saveApiKey('sk-abc');
        await service.clearApiKey();
        expect(await service.hasApiKey, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // apiKeyConfigured derived from secure storage
    // -----------------------------------------------------------------------
    group('apiKeyConfigured in loaded config', () {
      test('apiKeyConfigured is true after saving an API key', () async {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        await service.saveConfig(config);
        await service.saveApiKey('sk-live-key');

        final loaded = await service.loadConfig();
        expect(loaded.apiKeyConfigured, isTrue);
      });

      test('apiKeyConfigured is false when key is cleared', () async {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
          apiKeyConfigured: true,
        );
        await service.saveConfig(config);
        // no key saved — apiKeyConfigured should be false
        final loaded = await service.loadConfig();
        expect(loaded.apiKeyConfigured, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // loadApiKey
    // -----------------------------------------------------------------------
    group('loadApiKey', () {
      test('returns stored key value for provider construction', () async {
        await service.saveApiKey('sk-load-me');
        final key = await service.loadApiKey();
        expect(key, 'sk-load-me');
      });

      test('returns null when no key is stored', () async {
        final key = await service.loadApiKey();
        expect(key, isNull);
      });
    });
  });
}
