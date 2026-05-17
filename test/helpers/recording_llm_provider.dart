import 'package:grepink/services/llm_provider.dart';

class RecordingLlmProvider implements LlmProvider {
  final String responseText;
  final List<LlmRequest> requests = <LlmRequest>[];

  RecordingLlmProvider({this.responseText = '# Draft'});

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    requests.add(request);
    return LlmResponse(
      text: responseText,
      providerName: 'recording',
      model: 'recording-model',
    );
  }
}
