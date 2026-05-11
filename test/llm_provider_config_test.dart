import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/llm_provider_config.dart';

void main() {
  group('LlmProviderConfig', () {
    // -----------------------------------------------------------------------
    // Defaults
    // -----------------------------------------------------------------------
    group('defaults', () {
      test('default config has expected values', () {
        const config = LlmProviderConfig.defaults;
        expect(config.providerKind, LlmProviderKind.mock);
        expect(config.baseUrl, 'https://api.openai.com/v1');
        expect(config.model, 'gpt-4o-mini');
        expect(config.maxTokens, 900);
        expect(config.temperature, 0.2);
        expect(config.apiKeyConfigured, isFalse);
      });

      test('default config is valid', () {
        expect(LlmProviderConfig.defaults.isValid, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // Serialisation
    // -----------------------------------------------------------------------
    group('serialisation', () {
      test('round-trip via toJson / fromJson preserves all fields', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 500,
          temperature: 0.7,
          apiKeyConfigured: true,
        );

        final json = config.toJson();
        final restored = LlmProviderConfig.fromJson(json);

        expect(restored.providerKind, config.providerKind);
        expect(restored.baseUrl, config.baseUrl);
        expect(restored.model, config.model);
        expect(restored.maxTokens, config.maxTokens);
        expect(restored.temperature, config.temperature);
      });

      test('API key is NOT included in serialised JSON', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
          apiKeyConfigured: true,
        );

        final json = config.toJson();
        expect(json.containsKey('apiKey'), isFalse);
        expect(json.containsKey('apiKeyConfigured'), isFalse);

        final jsonString = config.toJsonString();
        expect(jsonString.contains('apiKey'), isFalse);
      });

      test('round-trip via JSON string', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'http://localhost:1234/v1',
          model: 'phi3',
          maxTokens: 1024,
          temperature: 0.5,
        );

        final restored = LlmProviderConfig.fromJsonString(config.toJsonString());

        expect(restored.baseUrl, config.baseUrl);
        expect(restored.model, config.model);
        expect(restored.maxTokens, config.maxTokens);
        expect(restored.temperature, config.temperature);
      });

      test('fromJson falls back to defaults for missing/unknown fields', () {
        final config = LlmProviderConfig.fromJson({'providerKind': 'unknown'});
        expect(config.providerKind, LlmProviderConfig.defaults.providerKind);
        expect(config.model, LlmProviderConfig.defaults.model);
      });
    });

    // -----------------------------------------------------------------------
    // Validation
    // -----------------------------------------------------------------------
    group('validation', () {
      test('openAICompatible with empty baseUrl is invalid', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: '',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        expect(config.isValid, isFalse);
        expect(config.validationErrors, isNotEmpty);
      });

      test('openAICompatible with empty model is invalid', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: '',
          maxTokens: 900,
          temperature: 0.2,
        );
        expect(config.isValid, isFalse);
      });

      test('temperature out of range is invalid', () {
        const tooHigh = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 900,
          temperature: 3.0,
        );
        const tooLow = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 900,
          temperature: -0.1,
        );
        expect(tooHigh.isValid, isFalse);
        expect(tooLow.isValid, isFalse);
      });

      test('maxTokens out of range is invalid', () {
        const tooMany = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 5000,
          temperature: 0.2,
        );
        const tooFew = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 10,
          temperature: 0.2,
        );
        expect(tooMany.isValid, isFalse);
        expect(tooFew.isValid, isFalse);
      });

      test('mock provider ignores empty baseUrl and model', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 900,
          temperature: 0.2,
        );
        expect(config.isValid, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // Clamping
    // -----------------------------------------------------------------------
    group('clamped()', () {
      test('clamps temperature above max', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 900,
          temperature: 5.0,
        );
        expect(config.clamped().temperature, LlmProviderConfig.kMaxTemperature);
      });

      test('clamps temperature below min', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 900,
          temperature: -1.0,
        );
        expect(config.clamped().temperature, LlmProviderConfig.kMinTemperature);
      });

      test('clamps maxTokens above max', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 9999,
          temperature: 0.2,
        );
        expect(config.clamped().maxTokens, LlmProviderConfig.kMaxTokens);
      });

      test('clamps maxTokens below min', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 1,
          temperature: 0.2,
        );
        expect(config.clamped().maxTokens, LlmProviderConfig.kMinTokens);
      });

      test('clamped() on an already-valid config is a no-op', () {
        const config = LlmProviderConfig.defaults;
        expect(config.clamped(), equals(config));
      });
    });

    // -----------------------------------------------------------------------
    // displayName
    // -----------------------------------------------------------------------
    group('displayName', () {
      test('mock provider has descriptive name', () {
        expect(LlmProviderConfig.defaults.displayName, contains('Mock'));
      });

      test('openAICompatible includes model in name', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
          maxTokens: 900,
          temperature: 0.2,
        );
        expect(config.displayName, contains('gpt-4o'));
      });
    });

    // -----------------------------------------------------------------------
    // copyWith
    // -----------------------------------------------------------------------
    group('copyWith', () {
      test('copyWith changes only the specified fields', () {
        final updated = LlmProviderConfig.defaults.copyWith(
          providerKind: LlmProviderKind.openAICompatible,
          model: 'gpt-4o',
        );
        expect(updated.providerKind, LlmProviderKind.openAICompatible);
        expect(updated.model, 'gpt-4o');
        expect(updated.baseUrl, LlmProviderConfig.defaults.baseUrl);
        expect(updated.maxTokens, LlmProviderConfig.defaults.maxTokens);
        expect(updated.temperature, LlmProviderConfig.defaults.temperature);
      });
    });
  });
}
