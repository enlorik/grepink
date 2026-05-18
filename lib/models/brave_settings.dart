import 'dart:convert';

import '../services/brave_evidence_provider.dart';

class BraveSettings {
  static const int kMinResultCount = 1;
  static const int kMaxResultCount = 20;

  final bool enabled;
  final int resultCount;
  final BraveSafeSearch safeSearch;
  final bool apiKeyConfigured;

  const BraveSettings({
    this.enabled = false,
    this.resultCount = 5,
    this.safeSearch = BraveSafeSearch.moderate,
    this.apiKeyConfigured = false,
  });

  static const defaults = BraveSettings();

  BraveSettings copyWith({
    bool? enabled,
    int? resultCount,
    BraveSafeSearch? safeSearch,
    bool? apiKeyConfigured,
  }) {
    return BraveSettings(
      enabled: enabled ?? this.enabled,
      resultCount: resultCount ?? this.resultCount,
      safeSearch: safeSearch ?? this.safeSearch,
      apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
    );
  }

  BraveSettings clamped() {
    return copyWith(
      resultCount: resultCount.clamp(kMinResultCount, kMaxResultCount),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'resultCount': resultCount,
      'safeSearch': safeSearch.name,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory BraveSettings.fromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return BraveSettings(
      enabled: decoded['enabled'] as bool? ?? defaults.enabled,
      resultCount: decoded['resultCount'] as int? ?? defaults.resultCount,
      safeSearch: _safeSearchFromName(
        decoded['safeSearch'] as String?,
      ),
    ).clamped();
  }

  static BraveSafeSearch _safeSearchFromName(String? value) {
    return BraveSafeSearch.values.firstWhere(
      (option) => option.name == value,
      orElse: () => BraveSafeSearch.moderate,
    );
  }
}
