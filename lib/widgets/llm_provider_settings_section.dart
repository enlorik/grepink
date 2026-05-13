import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/llm_provider_config.dart';
import '../providers/llm_settings_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Settings section widget for configuring the LLM provider.
///
/// Renders an "AI PROVIDER" section that matches the existing [SettingsScreen]
/// style.  Embed it directly in the [SettingsScreen] `ListView`.
class LlmProviderSettingsSection extends ConsumerStatefulWidget {
  const LlmProviderSettingsSection({super.key});

  @override
  ConsumerState<LlmProviderSettingsSection> createState() =>
      _LlmProviderSettingsSectionState();
}

class _LlmProviderSettingsSectionState
    extends ConsumerState<LlmProviderSettingsSection> {
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _apiKeyController;

  bool _apiKeyVisible = false;
  bool _controllersInitialized = false;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _modelController = TextEditingController();
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _initControllers(LlmProviderConfig config) {
    if (_controllersInitialized) return;
    _baseUrlController.text = config.baseUrl;
    _modelController.text = config.model;
    _controllersInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(llmSettingsProvider);

    return settingsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _buildSectionShell(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Could not load LLM settings: $e',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
      data: (config) {
        _initControllers(config);
        return _buildSectionShell(
          children: _buildChildren(config),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Section shell — matches SettingsScreen._buildSection style
  // ---------------------------------------------------------------------------

  Widget _buildSectionShell({required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text('AI PROVIDER', style: AppTextStyles.excerptSource),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.dividerBorder),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Row helper — matches SettingsScreen._buildSettingRow style
  // ---------------------------------------------------------------------------

  Widget _buildRow({
    required String title,
    String? subtitle,
    Widget? trailing,
    Widget? child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleMedium),
                    if (subtitle != null)
                      Text(subtitle, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child,
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Content builder
  // ---------------------------------------------------------------------------

  List<Widget> _buildChildren(LlmProviderConfig config) {
    final children = <Widget>[
      _buildRow(
        title: 'Provider',
        child: _buildProviderSelector(config),
      ),
    ];

    if (config.providerKind == LlmProviderKind.mock) {
      children.add(_buildMockNote());
    } else {
      children.addAll(_buildOpenAiFields(config));
    }

    final errors = config.validationErrors;
    if (errors.isNotEmpty) {
      children.add(_buildValidationErrors(errors));
    }

    return children;
  }

  // ---------------------------------------------------------------------------
  // Provider kind selector
  // ---------------------------------------------------------------------------

  Widget _buildProviderSelector(LlmProviderConfig config) {
    return DropdownButtonFormField<LlmProviderKind>(
      value: config.providerKind,
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(
          value: LlmProviderKind.mock,
          child: Text('Mock'),
        ),
        DropdownMenuItem(
          value: LlmProviderKind.openAICompatible,
          child: Text('OpenAI-compatible / Local AI'),
        ),
      ],
      onChanged: (kind) {
        if (kind != null) {
          ref.read(llmSettingsProvider.notifier).setProviderKind(kind);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Mock provider note
  // ---------------------------------------------------------------------------

  Widget _buildMockNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        'Mock provider is used for testing and offline-safe drafts.',
        style: AppTextStyles.bodySmall.copyWith(
          fontStyle: FontStyle.italic,
          color: AppColors.primaryAccent,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OpenAI-compatible fields
  // ---------------------------------------------------------------------------

  List<Widget> _buildOpenAiFields(LlmProviderConfig config) {
    return [
      _buildRow(
        title: 'Base URL',
        child: TextField(
          controller: _baseUrlController,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.bodyText),
          decoration: const InputDecoration(
            hintText: 'https://api.openai.com/v1',
            helperText:
                'e.g. https://api.openai.com/v1 · http://localhost:1234/v1 · http://127.0.0.1:11434/v1',
            helperMaxLines: 2,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onChanged: (v) =>
              ref.read(llmSettingsProvider.notifier).setBaseUrl(v),
        ),
      ),
      _buildRow(
        title: 'Model',
        child: TextField(
          controller: _modelController,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.bodyText),
          decoration: const InputDecoration(
            hintText: 'gpt-4o-mini',
            helperText: 'e.g. gpt-4o-mini · local-model · phi3',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onChanged: (v) =>
              ref.read(llmSettingsProvider.notifier).setModel(v),
        ),
      ),
      _buildRow(
        title: 'API Key',
        subtitle: config.apiKeyConfigured ? 'API key saved' : 'No API key saved',
        child: _buildApiKeyField(),
      ),
      _buildRow(
        title: 'Max Tokens',
        subtitle: '${config.maxTokens} tokens',
        child: Slider(
          value: config.maxTokens
              .clamp(
                LlmProviderConfig.kMinTokens,
                LlmProviderConfig.kMaxTokens,
              )
              .toDouble(),
          min: LlmProviderConfig.kMinTokens.toDouble(),
          max: LlmProviderConfig.kMaxTokens.toDouble(),
          divisions: (LlmProviderConfig.kMaxTokens - LlmProviderConfig.kMinTokens) ~/
              50,
          activeColor: AppColors.primaryAction,
          inactiveColor: AppColors.dividerBorder,
          label: config.maxTokens.toString(),
          onChanged: (v) =>
              ref.read(llmSettingsProvider.notifier).setMaxTokens(v.round()),
        ),
      ),
      _buildRow(
        title: 'Temperature',
        subtitle: config.temperature.toStringAsFixed(2),
        child: Slider(
          value: config.temperature.clamp(
            LlmProviderConfig.kMinTemperature,
            LlmProviderConfig.kMaxTemperature,
          ),
          min: LlmProviderConfig.kMinTemperature,
          max: LlmProviderConfig.kMaxTemperature,
          divisions: 20,
          activeColor: AppColors.primaryAction,
          inactiveColor: AppColors.dividerBorder,
          label: config.temperature.toStringAsFixed(2),
          onChanged: (v) => ref
              .read(llmSettingsProvider.notifier)
              .setTemperature(double.parse(v.toStringAsFixed(2))),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // API key field
  // ---------------------------------------------------------------------------

  Widget _buildApiKeyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _apiKeyController,
          obscureText: !_apiKeyVisible,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.bodyText,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'sk-...',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                _apiKeyVisible ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: AppColors.secondaryText,
              ),
              onPressed: () =>
                  setState(() => _apiKeyVisible = !_apiKeyVisible),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: () async {
                final key = _apiKeyController.text;
                await ref.read(llmSettingsProvider.notifier).saveApiKey(key);
                _apiKeyController.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
                foregroundColor: AppColors.surface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Save'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                await ref.read(llmSettingsProvider.notifier).clearApiKey();
                _apiKeyController.clear();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Validation errors
  // ---------------------------------------------------------------------------

  Widget _buildValidationErrors(List<String> errors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: errors
            .map(
              (e) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      e,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
