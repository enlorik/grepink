import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepink/models/llm_provider_config.dart';
import 'package:grepink/providers/llm_settings_provider.dart';

export 'package:grepink/models/llm_provider_config.dart';

class _FixedLlmSettingsNotifier extends LlmSettingsNotifier {
  final LlmProviderConfig _config;
  _FixedLlmSettingsNotifier(this._config);

  @override
  Future<LlmProviderConfig> build() async => _config;
}

Override llmSettingsOverride(LlmProviderConfig config) =>
    llmSettingsProvider.overrideWith(() => _FixedLlmSettingsNotifier(config));
