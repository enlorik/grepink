import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String apiKey;
  final int maxTokens;
  final bool aiEnabled;
  final double similarityThreshold;

  const AppSettings({
    this.apiKey = '',
    this.maxTokens = 120,
    this.aiEnabled = true,
    this.similarityThreshold = 0.72,
  });

  AppSettings copyWith({
    String? apiKey,
    int? maxTokens,
    bool? aiEnabled,
    double? similarityThreshold,
  }) {
    return AppSettings(
      apiKey: apiKey ?? this.apiKey,
      maxTokens: maxTokens ?? this.maxTokens,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
    );
  }
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _keyApiKey = 'api_key';
  static const _keyMaxTokens = 'max_tokens';
  static const _keyAiEnabled = 'ai_enabled';
  static const _keySimilarityThreshold = 'similarity_threshold';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      apiKey: prefs.getString(_keyApiKey) ?? '',
      maxTokens: prefs.getInt(_keyMaxTokens) ?? 120,
      aiEnabled: prefs.getBool(_keyAiEnabled) ?? true,
      similarityThreshold: prefs.getDouble(_keySimilarityThreshold) ?? 0.72,
    );
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, key);
    state = AsyncData((await future).copyWith(apiKey: key));
  }

  Future<void> setMaxTokens(int tokens) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMaxTokens, tokens);
    state = AsyncData((await future).copyWith(maxTokens: tokens));
  }

  Future<void> setAiEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAiEnabled, enabled);
    state = AsyncData((await future).copyWith(aiEnabled: enabled));
  }

  Future<void> setSimilarityThreshold(double threshold) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySimilarityThreshold, threshold);
    state = AsyncData((await future).copyWith(similarityThreshold: threshold));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
