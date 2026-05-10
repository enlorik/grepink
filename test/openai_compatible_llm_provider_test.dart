import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/llm_provider.dart';
import 'package:grepink/services/openai_compatible_llm_provider.dart';
import 'package:http/http.dart' as http;

class _FakeHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  _FakeHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

LlmRequest _request() => LlmRequest(
      systemPrompt: 'system prompt',
      userPrompt: 'user prompt',
      maxTokens: 321,
      temperature: 0.4,
    );

void main() {
  group('OpenAICompatibleLlmProvider', () {
    test('builds the correct HTTP request', () async {
      http.BaseRequest? capturedRequest;
      String? capturedBody;
      final provider = OpenAICompatibleLlmProvider(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'secret-key',
        model: 'gpt-test',
        httpClient: _FakeHttpClient((request) async {
          capturedRequest = request;
          capturedBody = await request.finalize().bytesToString();
          return http.Response(
            jsonEncode({
              'model': 'gpt-test',
              'choices': [
                {
                  'message': {'content': 'hello'},
                  'finish_reason': 'stop',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await provider.complete(_request());

      expect(capturedRequest?.method, 'POST');
      expect(
        capturedRequest?.url.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(capturedRequest?.headers['Content-Type'], 'application/json');

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['model'], 'gpt-test');
      expect(body['max_tokens'], 321);
      expect(body['temperature'], 0.4);
      expect(body['messages'], [
        {'role': 'system', 'content': 'system prompt'},
        {'role': 'user', 'content': 'user prompt'},
      ]);
    });

    test('includes Authorization only when apiKey is non-empty', () async {
      http.BaseRequest? withKeyRequest;
      http.BaseRequest? withoutKeyRequest;

      final withKeyProvider = OpenAICompatibleLlmProvider(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'abc123',
        model: 'local-model',
        httpClient: _FakeHttpClient((request) async {
          withKeyRequest = request;
          return http.Response(
            jsonEncode({
              'model': 'local-model',
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final withoutKeyProvider = OpenAICompatibleLlmProvider(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: '   ',
        model: 'local-model',
        httpClient: _FakeHttpClient((request) async {
          withoutKeyRequest = request;
          return http.Response(
            jsonEncode({
              'model': 'local-model',
              'choices': [
                {
                  'message': {'content': 'ok'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await withKeyProvider.complete(_request());
      await withoutKeyProvider.complete(_request());

      expect(withKeyRequest?.headers['Authorization'], 'Bearer abc123');
      expect(withoutKeyRequest?.headers.containsKey('Authorization'), isFalse);
    });

    test('parses a valid chat completion response', () async {
      final provider = OpenAICompatibleLlmProvider(
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'phi',
        httpClient: _FakeHttpClient((_) async => http.Response(
              jsonEncode({
                'id': 'chatcmpl_123',
                'model': 'phi',
                'usage': {
                  'prompt_tokens': 12,
                  'completion_tokens': 4,
                },
                'choices': [
                  {
                    'message': {'content': 'Structured answer'},
                    'finish_reason': 'stop',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      final response = await provider.complete(_request());

      expect(response.text, 'Structured answer');
      expect(response.providerName, 'openai-compatible');
      expect(response.model, 'phi');
      expect(response.rawMetadata?['id'], 'chatcmpl_123');
    });

    test('handles network, non-200, and malformed responses safely', () async {
      final networkProvider = OpenAICompatibleLlmProvider(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-test',
        httpClient: _FakeHttpClient((_) async => throw Exception('network down')),
      );
      final non200Provider = OpenAICompatibleLlmProvider(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-test',
        httpClient: _FakeHttpClient((_) async => http.Response(
              '{"error":"bad request"}',
              500,
              headers: {'content-type': 'application/json'},
            )),
      );
      final malformedProvider = OpenAICompatibleLlmProvider(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-test',
        httpClient: _FakeHttpClient((_) async => http.Response(
              'not-json',
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

      final networkResponse = await networkProvider.complete(_request());
      final non200Response = await non200Provider.complete(_request());
      final malformedResponse = await malformedProvider.complete(_request());

      expect(networkResponse.text, isEmpty);
      expect(non200Response.text, isEmpty);
      expect(malformedResponse.text, isEmpty);
      expect(non200Response.rawMetadata?['statusCode'], 500);
    });
  });
}
