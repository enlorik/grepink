import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/brave_settings.dart';
import '../services/brave_evidence_provider.dart';
import '../services/brave_settings_service.dart';

final braveSettingsServiceProvider =
    FutureProvider<BraveSettingsService>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final service = BraveSettingsService(prefs: prefs);
  return service;
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
    state = AsyncData(clamped.copyWith(
      searchKeyConfigured: _current.searchKeyConfigured,
      answersKeyConfigured: _current.answersKeyConfigured,
    ));
  }

  Future<void> setEnabled(bool enabled) =>
      _persist(_current.copyWith(enabled: enabled));

  Future<void> setResultCount(int resultCount) =>
      _persist(_current.copyWith(resultCount: resultCount));

  Future<void> setSafeSearch(BraveSafeSearch safeSearch) =>
      _persist(_current.copyWith(safeSearch: safeSearch));

  Future<void> saveSearchApiKey(String apiKey) async {
    final service = await _service;
    await service.saveSearchApiKey(apiKey);
    final hasKey = await service.hasSearchApiKey;
    state = AsyncData(_current.copyWith(searchKeyConfigured: hasKey));
  }

  Future<void> clearSearchApiKey() async {
    final service = await _service;
    await service.clearSearchApiKey();
    state = AsyncData(_current.copyWith(searchKeyConfigured: false));
  }

  Future<void> saveAnswersApiKey(String apiKey) async {
    final service = await _service;
    await service.saveAnswersApiKey(apiKey);
    final hasKey = await service.hasAnswersApiKey;
    state = AsyncData(_current.copyWith(answersKeyConfigured: hasKey));
  }

  Future<void> clearAnswersApiKey() async {
    final service = await _service;
    await service.clearAnswersApiKey();
    state = AsyncData(_current.copyWith(answersKeyConfigured: false));
  }

  // Legacy forwarding methods for callers that haven't migrated yet
  Future<void> saveApiKey(String apiKey) => saveSearchApiKey(apiKey);

  Future<void> clearApiKey() => clearSearchApiKey();
}

final braveSettingsProvider =
    AsyncNotifierProvider<BraveSettingsNotifier, BraveSettings>(
  BraveSettingsNotifier.new,
);
