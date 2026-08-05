import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer_provider_outcome.dart';
import 'package:grepink/services/brave_answers_grounded_answer_provider.dart';
import 'package:http/http.dart' as http;

// ─── Fake HTTP clients ────────────────────────────────────────────────────────

class _FakeStreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;
  _FakeStreamingClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}

class _ThrowingClient extends http.BaseClient {
  final Object _error;
  _ThrowingClient(this._error);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(_error);
}

// ─── SSE helpers ──────────────────────────────────────────────────────────────

List<int> _buildSseBody(List<String> contents) {
  final buffer = StringBuffer();
  for (final content in contents) {
    final frame = jsonEncode({
      'choices': [
        {
          'delta': {'content': content}
        }
      ]
    });
    buffer.write('data: $frame\n\n');
  }
  buffer.write('data: [DONE]\n\n');
  return utf8.encode(buffer.toString());
}

http.StreamedResponse _sseResponse(List<int> bytes) =>
    http.StreamedResponse(Stream.value(bytes), 200);

http.StreamedResponse _statusResponse(int statusCode) =>
    http.StreamedResponse(
        Stream<List<int>>.fromIterable(const []), statusCode);

BraveAnswersGroundedAnswerProvider _provider(
  Future<http.StreamedResponse> Function(http.BaseRequest) handler, {
  String apiKey = 'test-api-key',
}) =>
    BraveAnswersGroundedAnswerProvider(
      apiKey: apiKey,
      client: _FakeStreamingClient(handler),
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('BraveAnswersGroundedAnswerProvider', () {
    group('successful SSE responses', () {
      test('full SSE stream returns correct answerText and citation fields',
          () async {
        final citationJson = jsonEncode({
          'number': 1,
          'url': 'https://example.com/a',
          'snippet': 'A snippet.',
          'start_index': 0,
          'end_index': 10,
        });
        final body =
            _buildSseBody(['Claim one. Claim two.<citation>$citationJson</citation>']);

        final result = await _provider((_) async => _sseResponse(body))
            .fetchGroundedAnswer('What is X?');

        expect(result, isA<GroundedAnswerSuccess>());
        final answer = (result as GroundedAnswerSuccess).answer;
        expect(answer.answerText, 'Claim one. Claim two.');
        expect(answer.citations, hasLength(1));
        final c = answer.citations.first;
        expect(c.url, 'https://example.com/a');
        expect(c.snippet, 'A snippet.');
        expect(c.startIndex, 0);
        expect(c.endIndex, 10);
      });

      test('citation tag split across SSE chunks is parsed from assembled string',
          () async {
        final citationJson = jsonEncode({
          'number': 1,
          'url': 'https://split.example.com',
          'start_index': 0,
          'end_index': 12,
        });
        final mid = citationJson.length ~/ 2;
        final body = _buildSseBody([
          'Answer text.<citation>${citationJson.substring(0, mid)}',
          '${citationJson.substring(mid)}</citation>',
        ]);

        final result = await _provider((_) async => _sseResponse(body))
            .fetchGroundedAnswer('test?');

        expect(result, isA<GroundedAnswerSuccess>());
        final answer = (result as GroundedAnswerSuccess).answer;
        expect(answer.answerText, 'Answer text.');
        expect(answer.citations, hasLength(1));
        expect(answer.citations.first.url, 'https://split.example.com');
        expect(answer.citations.first.startIndex, 0);
        expect(answer.citations.first.endIndex, 12);
      });

      test('malformed citation JSON skips that citation but returns answer text',
          () async {
        final body = _buildSseBody(
            ['Answer text.<citation>NOT_VALID_JSON</citation>']);

        final result = await _provider((_) async => _sseResponse(body))
            .fetchGroundedAnswer('test?');

        expect(result, isA<GroundedAnswerSuccess>());
        final answer = (result as GroundedAnswerSuccess).answer;
        expect(answer.answerText, 'Answer text.');
        expect(answer.citations, isEmpty);
      });

      test('<usage> and unknown tags are stripped silently from answer text',
          () async {
        final body = _buildSseBody([
          'The answer is here.',
          '<usage>{"input_tokens":50,"output_tokens":50}</usage>',
          '<think>internal reasoning</think>',
        ]);

        final result = await _provider((_) async => _sseResponse(body))
            .fetchGroundedAnswer('test?');

        expect(result, isA<GroundedAnswerSuccess>());
        final answer = (result as GroundedAnswerSuccess).answer;
        expect(answer.answerText, 'The answer is here.');
      });

      test('answer empty after stripping tags returns GroundedAnswerEmpty',
          () async {
        final body = _buildSseBody([
          '<citation>${jsonEncode({'number': 1, 'url': 'https://x.com'})}</citation>',
          '<usage>{"tokens":5}</usage>',
        ]);

        final result = await _provider((_) async => _sseResponse(body))
            .fetchGroundedAnswer('test?');

        expect(result, isA<GroundedAnswerEmpty>());
      });

      test('providerName is set to Brave Answers', () async {
        final body = _buildSseBody(['An answer.']);

        final result = await _provider((_) async => _sseResponse(body))
            .fetchGroundedAnswer('test?');

        expect(result, isA<GroundedAnswerSuccess>());
        expect(
            (result as GroundedAnswerSuccess).answer.providerName,
            'Brave Answers');
      });

      test('API key does not appear in any field of the returned answer',
          () async {
        const apiKey = 'super-secret-brave-key-xyz';
        final body = _buildSseBody(['Normal answer text.']);
        final provider = BraveAnswersGroundedAnswerProvider(
          apiKey: apiKey,
          client: _FakeStreamingClient((_) async => _sseResponse(body)),
        );

        final result = await provider.fetchGroundedAnswer('test?');

        expect(result, isA<GroundedAnswerSuccess>());
        final answer = (result as GroundedAnswerSuccess).answer;
        expect(answer.answerText, isNot(contains(apiKey)));
        expect(answer.question, isNot(contains(apiKey)));
        expect(answer.providerName, isNot(contains(apiKey)));
        for (final c in answer.citations) {
          expect(c.url, isNot(contains(apiKey)));
          expect(c.title, isNot(contains(apiKey)));
          expect(c.snippet ?? '', isNot(contains(apiKey)));
        }
      });
    });

    group('HTTP error status codes', () {
      test('HTTP 402 returns GroundedAnswerPlanUnavailable', () async {
        expect(
          await _provider((_) async => _statusResponse(402))
              .fetchGroundedAnswer('test?'),
          isA<GroundedAnswerPlanUnavailable>(),
        );
      });

      test('HTTP 403 returns GroundedAnswerUnauthorized', () async {
        expect(
          await _provider((_) async => _statusResponse(403))
              .fetchGroundedAnswer('test?'),
          isA<GroundedAnswerUnauthorized>(),
        );
      });

      test('HTTP 429 returns GroundedAnswerRateLimited', () async {
        expect(
          await _provider((_) async => _statusResponse(429))
              .fetchGroundedAnswer('test?'),
          isA<GroundedAnswerRateLimited>(),
        );
      });

      test('HTTP 500 returns GroundedAnswerNetworkFailure', () async {
        expect(
          await _provider((_) async => _statusResponse(500))
              .fetchGroundedAnswer('test?'),
          isA<GroundedAnswerNetworkFailure>(),
        );
      });

      test('HTTP 503 returns GroundedAnswerNetworkFailure', () async {
        expect(
          await _provider((_) async => _statusResponse(503))
              .fetchGroundedAnswer('test?'),
          isA<GroundedAnswerNetworkFailure>(),
        );
      });
    });

    group('network errors', () {
      test('SocketException returns GroundedAnswerNetworkFailure', () async {
        final provider = BraveAnswersGroundedAnswerProvider(
          apiKey: 'test-key',
          client: _ThrowingClient(const SocketException('network unreachable')),
        );

        expect(
          await provider.fetchGroundedAnswer('test?'),
          isA<GroundedAnswerNetworkFailure>(),
        );
      });

      test('IOException returns GroundedAnswerNetworkFailure', () async {
        final provider = BraveAnswersGroundedAnswerProvider(
          apiKey: 'test-key',
          client: _ThrowingClient(const HttpException('connection failed')),
        );

        expect(
          await provider.fetchGroundedAnswer('test?'),
          isA<GroundedAnswerNetworkFailure>(),
        );
      });
    });
  });
}
