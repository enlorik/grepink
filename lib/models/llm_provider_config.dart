import 'dart:convert';

/// Which LLM back-end to use.
enum LlmProviderKind {
  /// In-process mock — safe default, no API key required.
  mock,

  /// Any OpenAI-compatible REST API (OpenAI, local llama.cpp/Ollama, LAN hosts…).
  openAICompatible,
}

/// Immutable, non-sensitive configuration for an LLM provider.
///
/// The raw API key is intentionally **not** stored here; see
/// [LlmSettingsService] which keeps it in Flutter Secure Storage.
class LlmProviderConfig {
  final LlmProviderKind providerKind;

  /// Base URL for OpenAI-compatible providers.
  ///
  /// Examples:
  ///   - https://api.openai.com/v1   (OpenAI)
  ///   - http://localhost:1234/v1     (local llama.cpp / LM Studio)
  ///   - http://127.0.0.1:11434/v1   (Ollama)
  final String baseUrl;

  final String model;

  /// Maximum tokens to request.  Clamped to [kMinTokens]..[kMaxTokens].
  final int maxTokens;

  /// Sampling temperature.  Clamped to [kMinTemperature]..[kMaxTemperature].
  final double temperature;

  /// Whether an API key has been stored separately in secure storage.
  /// Does **not** hold the key itself.
  final bool apiKeyConfigured;

  static const int kMinTokens = 50;
  static const int kMaxTokens = 4000;
  static const double kMinTemperature = 0.0;
  static const double kMaxTemperature = 2.0;

  const LlmProviderConfig({
    required this.providerKind,
    required this.baseUrl,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    this.apiKeyConfigured = false,
  });

  /// Safe default: mock provider so nothing breaks without an API key.
  static const LlmProviderConfig defaults = LlmProviderConfig(
    providerKind: LlmProviderKind.mock,
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    maxTokens: 900,
    temperature: 0.2,
  );

  /// Human-readable label for display.
  String get displayName => switch (providerKind) {
        LlmProviderKind.mock => 'Mock LLM',
        LlmProviderKind.openAICompatible => 'OpenAI-compatible ($model)',
      };

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Returns a list of human-readable error messages, or empty if valid.
  List<String> get validationErrors {
    final errors = <String>[];
    if (providerKind == LlmProviderKind.openAICompatible) {
      if (baseUrl.trim().isEmpty) {
        errors.add('baseUrl must not be empty for OpenAI-compatible providers');
      }
      if (model.trim().isEmpty) {
        errors.add('model must not be empty for OpenAI-compatible providers');
      }
    }
    if (temperature < kMinTemperature || temperature > kMaxTemperature) {
      errors.add(
        'temperature must be between $kMinTemperature and $kMaxTemperature',
      );
    }
    if (maxTokens < kMinTokens || maxTokens > kMaxTokens) {
      errors.add(
        'maxTokens must be between $kMinTokens and $kMaxTokens',
      );
    }
    return errors;
  }

  bool get isValid => validationErrors.isEmpty;

  // ---------------------------------------------------------------------------
  // Clamped copy helper
  // ---------------------------------------------------------------------------

  /// Returns a copy with [temperature] and [maxTokens] clamped to valid ranges.
  LlmProviderConfig clamped() {
    return LlmProviderConfig(
      providerKind: providerKind,
      baseUrl: baseUrl,
      model: model,
      maxTokens: maxTokens.clamp(kMinTokens, kMaxTokens),
      temperature: temperature.clamp(kMinTemperature, kMaxTemperature),
      apiKeyConfigured: apiKeyConfigured,
    );
  }

  LlmProviderConfig copyWith({
    LlmProviderKind? providerKind,
    String? baseUrl,
    String? model,
    int? maxTokens,
    double? temperature,
    bool? apiKeyConfigured,
  }) {
    return LlmProviderConfig(
      providerKind: providerKind ?? this.providerKind,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialisation  (API key deliberately excluded)
  // ---------------------------------------------------------------------------

  Map<String, Object?> toJson() => {
        'providerKind': providerKind.name,
        'baseUrl': baseUrl,
        'model': model,
        'maxTokens': maxTokens,
        'temperature': temperature,
        // apiKeyConfigured is derived at load-time from secure storage; omit.
      };

  factory LlmProviderConfig.fromJson(Map<String, Object?> json) {
    final kindName = json['providerKind'] as String? ?? '';
    final kind = LlmProviderKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => LlmProviderConfig.defaults.providerKind,
    );
    return LlmProviderConfig(
      providerKind: kind,
      baseUrl: json['baseUrl'] as String? ?? LlmProviderConfig.defaults.baseUrl,
      model: json['model'] as String? ?? LlmProviderConfig.defaults.model,
      maxTokens:
          (json['maxTokens'] as num?)?.toInt() ??
          LlmProviderConfig.defaults.maxTokens,
      temperature:
          (json['temperature'] as num?)?.toDouble() ??
          LlmProviderConfig.defaults.temperature,
    );
  }

  /// Convenience round-trip via JSON string (for SharedPreferences).
  String toJsonString() => jsonEncode(toJson());

  factory LlmProviderConfig.fromJsonString(String source) =>
      LlmProviderConfig.fromJson(
        jsonDecode(source) as Map<String, Object?>,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmProviderConfig &&
          runtimeType == other.runtimeType &&
          providerKind == other.providerKind &&
          baseUrl == other.baseUrl &&
          model == other.model &&
          maxTokens == other.maxTokens &&
          temperature == other.temperature &&
          apiKeyConfigured == other.apiKeyConfigured;

  @override
  int get hashCode => Object.hash(
        providerKind,
        baseUrl,
        model,
        maxTokens,
        temperature,
        apiKeyConfigured,
      );
}
