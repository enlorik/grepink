import '../models/llm_provider_config.dart';
import 'summary_writer.dart';
import 'structured_summary_writer.dart';
import 'llm_provider_factory.dart';
import 'llm_settings_service.dart';

class ConfiguredSummaryWriterFactory {
  final LlmSettingsService _settingsService;
  final LlmProviderFactory _providerFactory;

  const ConfiguredSummaryWriterFactory({
    required LlmSettingsService settingsService,
    LlmProviderFactory providerFactory = const LlmProviderFactory(),
  })  : _settingsService = settingsService,
        _providerFactory = providerFactory;

  Future<SummaryWriter> create() async {
    final persistedConfig = await _settingsService.loadConfig();
    final config = persistedConfig.isValid
        ? persistedConfig
        : _fallbackConfigFor(persistedConfig);
    final apiKey = config.providerKind == persistedConfig.providerKind
        ? await _settingsService.loadApiKey()
        : null;
    final provider = _providerFactory.create(config, apiKey: apiKey);

    return StructuredSummaryWriter(
      llmProvider: provider,
      maxTokens: config.maxTokens,
      temperature: config.temperature,
    );
  }

  LlmProviderConfig _fallbackConfigFor(LlmProviderConfig invalidConfig) {
    return LlmProviderConfig.defaults.copyWith(
      maxTokens:
          invalidConfig.maxTokens.clamp(
                LlmProviderConfig.kMinTokens,
                LlmProviderConfig.kMaxTokens,
              )
              ,
      temperature:
          invalidConfig.temperature.clamp(
                LlmProviderConfig.kMinTemperature,
                LlmProviderConfig.kMaxTemperature,
              )
              ,
    );
  }
}
