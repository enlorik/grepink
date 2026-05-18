import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brave_settings.dart';
import '../services/brave_evidence_provider.dart';
import '../services/brave_settings_service.dart';

final braveSettingsServiceProvider =
    FutureProvider<BraveSettingsService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return BraveSettingsService(prefs: prefs);
});

class BraveSettingsNotifier extends AsyncNotifier<BraveSettings> {
  @override
  Future<BraveSettings> build() async {
    final service = await ref.watch(braveSettingsServiceProvider.future);
    return service.loadSettings();
  }

  Future<BraveSettingsService> get _service =>
      ref.read(braveSettingsServiceProvider.future);

  BraveSettings get _current => state.valueOrNull ?? BraveSettings.defaults;

  Future<void> _persist(BraveSettings updated) async {
    final service = await _service;
    final clamped = updated.clamped();
    await service.saveSettings(clamped);
    state = AsyncData(clamped.copyWith(apiKeyConfigured: _current.apiKeyConfigured));
  }

  Future<void> setEnabled(bool enabled) =>
      _persist(_current.copyWith(enabled: enabled));

  Future<void> setResultCount(int resultCount) =>
      _persist(_current.copyWith(resultCount: resultCount));

  Future<void> setSafeSearch(BraveSafeSearch safeSearch) =>
      _persist(_current.copyWith(safeSearch: safeSearch));

  Future<void> saveApiKey(String apiKey) async {
    final service = await _service;
    await service.saveApiKey(apiKey);
    final hasKey = await service.hasApiKey;
    state = AsyncData(_current.copyWith(apiKeyConfigured: hasKey));
  }

  Future<void> clearApiKey() async {
    final service = await _service;
    await service.clearApiKey();
    state = AsyncData(_current.copyWith(apiKeyConfigured: false));
  }
}

final braveSettingsProvider =
    AsyncNotifierProvider<BraveSettingsNotifier, BraveSettings>(
  BraveSettingsNotifier.new,
);
