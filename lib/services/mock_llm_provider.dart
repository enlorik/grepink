import 'llm_provider.dart';

class MockLlmProvider implements LlmProvider {
  final String responseText;
  final String providerName;
  final String model;
  final List<LlmRequest> requests = <LlmRequest>[];

  MockLlmProvider({
    this.responseText = '## Suggested markdown to save\n\n- Mock LLM response',
    this.providerName = 'mock-llm',
    this.model = 'mock-model',
  });

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    requests.add(request);
    return LlmResponse(
      text: responseText,
      providerName: providerName,
      model: model,
      rawMetadata: {
        'requestCount': requests.length,
      },
    );
  }
}
