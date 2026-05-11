class LlmRequest {
  final String systemPrompt;
  final String userPrompt;
  final int maxTokens;
  final double temperature;

  LlmRequest({
    required this.systemPrompt,
    required this.userPrompt,
    this.maxTokens = 800,
    this.temperature = 0.2,
  });
}

class LlmResponse {
  final String text;
  final String providerName;
  final String model;
  final Map<String, Object?>? rawMetadata;

  LlmResponse({
    required this.text,
    required this.providerName,
    required this.model,
    Map<String, Object?>? rawMetadata,
  }) : rawMetadata =
            rawMetadata == null
                ? null
                : Map<String, Object?>.unmodifiable(rawMetadata);

  factory LlmResponse.empty({
    required String providerName,
    required String model,
    Map<String, Object?>? rawMetadata,
  }) {
    return LlmResponse(
      text: '',
      providerName: providerName,
      model: model,
      rawMetadata: rawMetadata,
    );
  }
}

abstract class LlmProvider {
  Future<LlmResponse> complete(LlmRequest request);
}
