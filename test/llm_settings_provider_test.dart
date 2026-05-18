import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/llm_provider_config.dart';
import 'package:grepink/providers/llm_settings_provider.dart';
import 'package:grepink/services/llm_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [ProviderContainer] whose [llmSettingsServiceProvider] is backed
/// by in-memory fakes so no native channels are needed.
Future<(ProviderContainer, FakeSecureStorage, SharedPreferences)>
    _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secureStorage = FakeSecureStorage();
  final service = LlmSettingsService(
    prefs: prefs,
    secureStorage: secureStorage,
  );

  final container = ProviderContainer(
    overrides: [
      llmSettingsServiceProvider.overrideWith((_) async => service),
    ],
  );

  return (container, secureStorage, prefs);
}

void main() {
  group('LlmSettingsNotifier', () {
    late ProviderContainer container;
    late FakeSecureStorage secureStorage;
    late SharedPreferences prefs;

    setUp(() async {
      (container, secureStorage, prefs) = await _makeContainer();
    });

    tearDown(() => container.dispose());

    // -----------------------------------------------------------------------
    // Default state
    // -----------------------------------------------------------------------
    group('initial state', () {
      test('loads LlmProviderConfig.defaults when nothing is persisted',
          () async {
        await container.read(llmSettingsProvider.future);
        final config = container.read(llmSettingsProvider).valueOrNull!;

        expect(config.providerKind, LlmProviderConfig.defaults.providerKind);
        expect(config.baseUrl, LlmProviderConfig.defaults.baseUrl);
        expect(config.model, LlmProviderConfig.defaults.model);
        expect(config.maxTokens, LlmProviderConfig.defaults.maxTokens);
        expect(config.temperature, LlmProviderConfig.defaults.temperature);
        expect(config.apiKeyConfigured, isFalse);
      });
    });

    // -----------------------------------------------------------------------
    // setProviderKind
    // -----------------------------------------------------------------------
    group('setProviderKind', () {
      test('switches to openAICompatible and persists config', () async {
        await container.read(llmSettingsProvider.future);

        await container
            .read(llmSettingsProvider.notifier)
            .setProviderKind(LlmProviderKind.openAICompatible);

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.providerKind, LlmProviderKind.openAICompatible);

        // Verify persisted in SharedPreferences
        final rawJson = prefs.getString('llm_provider_config') ?? '';
        expect(rawJson.contains('openAICompatible'), isTrue);
      });

      test('switching back to mock persists mock kind', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setProviderKind(LlmProviderKind.openAICompatible);
        await container
            .read(llmSettingsProvider.notifier)
            .setProviderKind(LlmProviderKind.mock);

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.providerKind, LlmProviderKind.mock);
      });
    });

    // -----------------------------------------------------------------------
    // setBaseUrl / setModel
    // -----------------------------------------------------------------------
    group('setBaseUrl', () {
      test('updates baseUrl in state and persists it', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setBaseUrl('http://localhost:1234/v1');

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.baseUrl, 'http://localhost:1234/v1');

        final rawJson = prefs.getString('llm_provider_config') ?? '';
        expect(rawJson.contains('localhost'), isTrue);
      });
    });

    group('setModel', () {
      test('updates model in state and persists it', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setModel('phi3');

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.model, 'phi3');

        final rawJson = prefs.getString('llm_provider_config') ?? '';
        expect(rawJson.contains('phi3'), isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // setMaxTokens / setTemperature
    // -----------------------------------------------------------------------
    group('setMaxTokens', () {
      test('clamps to valid range', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setMaxTokens(99999);

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.maxTokens, LlmProviderConfig.kMaxTokens);
      });

      test('persists a valid value', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setMaxTokens(512);

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.maxTokens, 512);
      });
    });

    group('setTemperature', () {
      test('clamps temperature above max', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setTemperature(5.0);

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.temperature, LlmProviderConfig.kMaxTemperature);
      });

      test('persists a valid temperature', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .setTemperature(0.8);

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.temperature, closeTo(0.8, 0.001));
      });
    });

    // -----------------------------------------------------------------------
    // API key
    // -----------------------------------------------------------------------
    group('saveApiKey', () {
      test('stores key in secure storage, not SharedPreferences', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .saveApiKey('sk-test');

        // Must be in secure storage
        expect(secureStorage.data.containsKey('llm_api_key'), isTrue);
        expect(secureStorage.data['llm_api_key'], 'sk-test');

        // Must NOT be in SharedPreferences
        for (final key in prefs.getKeys()) {
          final value = prefs.get(key)?.toString() ?? '';
          expect(
            value.contains('sk-test'),
            isFalse,
            reason: 'API key found in SharedPreferences under "$key"',
          );
        }
      });

      test('updates apiKeyConfigured to true in state', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .saveApiKey('sk-test');

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.apiKeyConfigured, isTrue);
      });

      test('raw API key is not exposed in state', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .saveApiKey('sk-super-secret');

        final config = container.read(llmSettingsProvider).valueOrNull!;
        // The state object must not contain the raw key string
        expect(config.toString().contains('sk-super-secret'), isFalse);
      });
    });

    group('clearApiKey', () {
      test('removes key from secure storage', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .saveApiKey('sk-to-clear');
        await container.read(llmSettingsProvider.notifier).clearApiKey();

        expect(secureStorage.data.containsKey('llm_api_key'), isFalse);
      });

      test('updates apiKeyConfigured to false in state', () async {
        await container.read(llmSettingsProvider.future);
        await container
            .read(llmSettingsProvider.notifier)
            .saveApiKey('sk-abc');
        await container.read(llmSettingsProvider.notifier).clearApiKey();

        final config = container.read(llmSettingsProvider).valueOrNull!;
        expect(config.apiKeyConfigured, isFalse);
      });

      test('is safe to call when no key is stored', () async {
        await container.read(llmSettingsProvider.future);
        await expectLater(
          container.read(llmSettingsProvider.notifier).clearApiKey(),
          completes,
        );
      });
    });
  });
}
