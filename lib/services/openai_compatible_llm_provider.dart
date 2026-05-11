import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_provider.dart';

class OpenAICompatibleLlmProvider implements LlmProvider {
  final String _baseUrl;
  final String _apiKey;
  final String _model;
  final http.Client _httpClient;

  OpenAICompatibleLlmProvider({
    required String baseUrl,
    required String model,
    String? apiKey,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey ?? '',
        _model = model,
        _httpClient = httpClient ?? http.Client();

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    final apiKey = _apiKey.trim();
    http.Response response;
    try {
      response = await _httpClient.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {
              'role': 'system',
              'content': request.systemPrompt,
            },
            {
              'role': 'user',
              'content': request.userPrompt,
            },
          ],
          'max_tokens': request.maxTokens,
          'temperature': request.temperature,
        }),
      );
    } catch (error) {
      return LlmResponse.empty(
        providerName: 'openai-compatible',
        model: _model,
        rawMetadata: {
          'baseUrl': _baseUrl,
          'error': error.toString(),
        },
      );
    }

    if (response.statusCode != 200) {
      return LlmResponse.empty(
        providerName: 'openai-compatible',
        model: _model,
        rawMetadata: {
          'baseUrl': _baseUrl,
          'statusCode': response.statusCode,
          'body': response.body,
        },
      );
    }

    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      return LlmResponse.empty(
        providerName: 'openai-compatible',
        model: _model,
        rawMetadata: {
          'baseUrl': _baseUrl,
          'error': error.toString(),
          'body': response.body,
        },
      );
    }

    final choices = payload['choices'];
    if (choices is! List || choices.isEmpty) {
      return LlmResponse.empty(
        providerName: 'openai-compatible',
        model: _model,
        rawMetadata: {
          'baseUrl': _baseUrl,
          'body': payload,
        },
      );
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      return LlmResponse.empty(
        providerName: 'openai-compatible',
        model: _model,
        rawMetadata: {
          'baseUrl': _baseUrl,
          'body': payload,
        },
      );
    }

    final message = firstChoice['message'];
    final text = _extractContent(message).trim();
    return LlmResponse(
      text: text,
      providerName: 'openai-compatible',
      model: payload['model'] is String ? payload['model'] as String : _model,
      rawMetadata: {
        'baseUrl': _baseUrl,
        'id': payload['id'],
        'finishReason': firstChoice['finish_reason'],
        'usage': _mapOrNull(payload['usage']),
      },
    );
  }

  Uri get _endpoint {
    final normalizedBaseUrl = _baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBaseUrl/chat/completions');
  }

  String _extractContent(Object? message) {
    if (message is! Map<String, dynamic>) return '';
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join('\n')
          .trim();
    }
    return '';
  }

  Map<String, Object?>? _mapOrNull(Object? value) {
    if (value is! Map) return null;
    return value.map<String, Object?>(
      (key, val) => MapEntry(key.toString(), val),
    );
  }
}
