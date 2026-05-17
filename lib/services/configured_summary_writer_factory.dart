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
    final config = await _settingsService.loadConfig();
    final apiKey = await _settingsService.loadApiKey();
    final provider = _providerFactory.create(config, apiKey: apiKey);

    return StructuredSummaryWriter(
      llmProvider: provider,
      maxTokens: config.maxTokens,
      temperature: config.temperature,
    );
  }
}
