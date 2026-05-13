import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm_provider_config.dart';
import '../services/llm_settings_service.dart';

// ---------------------------------------------------------------------------
// Service provider (override in tests to inject fakes)
// ---------------------------------------------------------------------------

/// Provides the [LlmSettingsService] used by [LlmSettingsNotifier].
///
/// Override this in tests to inject a fake:
/// ```dart
/// llmSettingsServiceProvider.overrideWith((ref) async => fakeService)
/// ```
final llmSettingsServiceProvider = FutureProvider<LlmSettingsService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return LlmSettingsService(prefs: prefs);
});

// ---------------------------------------------------------------------------
// State notifier
// ---------------------------------------------------------------------------

/// Loads and persists [LlmProviderConfig] through [LlmSettingsService].
///
/// The raw API key is never placed into the [AsyncData] state; only
/// [LlmProviderConfig.apiKeyConfigured] (a bool) is exposed.
class LlmSettingsNotifier extends AsyncNotifier<LlmProviderConfig> {
  @override
  Future<LlmProviderConfig> build() async {
    final service = await ref.watch(llmSettingsServiceProvider.future);
    return service.loadConfig();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Future<LlmSettingsService> get _service =>
      ref.read(llmSettingsServiceProvider.future);

  LlmProviderConfig get _current =>
      state.valueOrNull ?? LlmProviderConfig.defaults;

  Future<void> _persist(LlmProviderConfig updated) async {
    final service = await _service;
    await service.saveConfig(updated);
    state = AsyncData(updated);
  }

  // -------------------------------------------------------------------------
  // Provider config updates
  // -------------------------------------------------------------------------

  Future<void> setProviderKind(LlmProviderKind kind) =>
      _persist(_current.copyWith(providerKind: kind).clamped());

  Future<void> setBaseUrl(String url) =>
      _persist(_current.copyWith(baseUrl: url).clamped());

  Future<void> setModel(String model) =>
      _persist(_current.copyWith(model: model).clamped());

  Future<void> setMaxTokens(int maxTokens) =>
      _persist(_current.copyWith(maxTokens: maxTokens).clamped());

  Future<void> setTemperature(double temperature) =>
      _persist(_current.copyWith(temperature: temperature).clamped());

  // -------------------------------------------------------------------------
  // API key (sensitive — never stored in app state)
  // -------------------------------------------------------------------------

  /// Saves [apiKey] to secure storage only.  After saving, updates
  /// [LlmProviderConfig.apiKeyConfigured] in state but does not retain the
  /// raw key value.
  Future<void> saveApiKey(String apiKey) async {
    final service = await _service;
    await service.saveApiKey(apiKey);
    final hasKey = await service.hasApiKey;
    state = AsyncData(_current.copyWith(apiKeyConfigured: hasKey));
  }

  /// Removes the API key from secure storage and clears [apiKeyConfigured].
  Future<void> clearApiKey() async {
    final service = await _service;
    await service.clearApiKey();
    state = AsyncData(_current.copyWith(apiKeyConfigured: false));
  }
}

// ---------------------------------------------------------------------------
// Public provider
// ---------------------------------------------------------------------------

final llmSettingsProvider =
    AsyncNotifierProvider<LlmSettingsNotifier, LlmProviderConfig>(
  LlmSettingsNotifier.new,
);
