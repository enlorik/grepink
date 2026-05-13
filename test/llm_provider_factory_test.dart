import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/llm_provider_config.dart';
import 'package:grepink/services/llm_provider_factory.dart';
import 'package:grepink/services/mock_llm_provider.dart';
import 'package:grepink/services/openai_compatible_llm_provider.dart';

void main() {
  group('LlmProviderFactory', () {
    const factory = LlmProviderFactory();

    // -----------------------------------------------------------------------
    // Mock
    // -----------------------------------------------------------------------
    group('mock config', () {
      test('creates MockLlmProvider for LlmProviderKind.mock', () {
        const config = LlmProviderConfig.defaults; // defaults are mock
        final provider = factory.create(config);
        expect(provider, isA<MockLlmProvider>());
      });

      test('mock provider works without an API key', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.mock,
          baseUrl: '',
          model: '',
          maxTokens: 900,
          temperature: 0.2,
        );
        final provider = factory.create(config);
        expect(provider, isA<MockLlmProvider>());
      });

      test('mock provider ignores a supplied API key', () {
        final provider = factory.create(
          LlmProviderConfig.defaults,
          apiKey: 'should-be-ignored',
        );
        expect(provider, isA<MockLlmProvider>());
      });
    });

    // -----------------------------------------------------------------------
    // OpenAI-compatible
    // -----------------------------------------------------------------------
    group('openAICompatible config', () {
      test('creates OpenAICompatibleLlmProvider', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        final provider = factory.create(config);
        expect(provider, isA<OpenAICompatibleLlmProvider>());
      });

      test('creates OpenAICompatibleLlmProvider without API key', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'http://localhost:1234/v1',
          model: 'phi3',
          maxTokens: 512,
          temperature: 0.5,
        );
        // Should not throw even when apiKey is null (local AI needs no key).
        final provider = factory.create(config);
        expect(provider, isA<OpenAICompatibleLlmProvider>());
      });

      test('creates OpenAICompatibleLlmProvider with API key', () {
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o',
          maxTokens: 1000,
          temperature: 0.3,
          apiKeyConfigured: true,
        );
        final provider = factory.create(config, apiKey: 'sk-test');
        expect(provider, isA<OpenAICompatibleLlmProvider>());
      });
    });

    // -----------------------------------------------------------------------
    // Each kind is distinct
    // -----------------------------------------------------------------------
    test('mock and openAICompatible produce different provider types', () {
      const mockConfig = LlmProviderConfig(
        providerKind: LlmProviderKind.mock,
        baseUrl: '',
        model: '',
        maxTokens: 900,
        temperature: 0.2,
      );
      const openAiConfig = LlmProviderConfig(
        providerKind: LlmProviderKind.openAICompatible,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        maxTokens: 900,
        temperature: 0.2,
      );

      expect(
        factory.create(mockConfig).runtimeType,
        isNot(factory.create(openAiConfig).runtimeType),
      );
    });
  });
}
