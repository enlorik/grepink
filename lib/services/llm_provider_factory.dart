import '../models/llm_provider_config.dart';
import 'llm_provider.dart';
import 'mock_llm_provider.dart';
import 'openai_compatible_llm_provider.dart';

/// Creates a concrete [LlmProvider] from an [LlmProviderConfig] and an
/// optional API key.
///
/// Keep this small: configuration decisions live in [LlmProviderConfig] and
/// [LlmSettingsService]; this factory is only responsible for object
/// construction.
class LlmProviderFactory {
  const LlmProviderFactory();

  /// Returns a [LlmProvider] for the given [config].
  ///
  /// - [LlmProviderKind.mock] → [MockLlmProvider] (ignores [apiKey])
  /// - [LlmProviderKind.openAICompatible] → [OpenAICompatibleLlmProvider]
  ///
  /// [apiKey] is taken from [LlmSettingsService.loadApiKey] by the caller and
  /// passed here; it is never stored on this factory.
  LlmProvider create(LlmProviderConfig config, {String? apiKey}) {
    return switch (config.providerKind) {
      LlmProviderKind.mock => MockLlmProvider(),
      LlmProviderKind.openAICompatible => OpenAICompatibleLlmProvider(
          baseUrl: config.baseUrl,
          model: config.model,
          apiKey: apiKey,
        ),
    };
  }
}
