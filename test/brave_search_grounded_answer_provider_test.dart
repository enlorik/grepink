import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grepink/models/brave_settings.dart';
import 'package:grepink/services/brave_search_grounded_answer_provider.dart';

void main() {
  const configured = BraveSettings(
    enabled: true,
    apiKeyConfigured: true,
    resultCount: 5,
  );

  test('isConfigured follows Brave enabled and stored-key settings', () {
    final disabled = BraveSearchGroundedAnswerProvider(
      settings: BraveSettings.defaults,
      apiKeyLoader: () async => 'key',
    );
    final enabled = BraveSearchGroundedAnswerProvider(
      settings: configured,
      apiKeyLoader: () async => 'key',
    );

    expect(disabled.isConfigured, isFalse);
    expect(enabled.isConfigured, isTrue);
  });

  test('maps Brave results into grounded text and citations', () async {
    final client = MockClient((request) async {
      expect(request.headers['X-Subscription-Token'], 'brave-key');
      expect(request.url.queryParameters['q'], 'What is Flutter?');
      return http.Response(
        jsonEncode({
          'web': {
            'results': [
              {
                'url': 'https://docs.flutter.dev',
                'title': 'Flutter documentation',
                'description': 'Flutter builds multiplatform applications.',
              },
              {
                'url': 'https://dart.dev',
                'title': 'Dart',
                'description': 'Flutter applications are written in Dart.',
              },
            ],
          },
        }),
        200,
      );
    });

    final provider = BraveSearchGroundedAnswerProvider(
      settings: configured,
      apiKeyLoader: () async => 'brave-key',
      httpClient: client,
      now: () => DateTime.utc(2026, 7, 24, 20),
    );

    final answer = await provider.fetchGroundedAnswer(' What is Flutter? ');

    expect(answer, isNotNull);
    expect(answer!.question, 'What is Flutter?');
    expect(answer.providerName, 'Brave Search');
    expect(answer.rawSourceLabel, 'brave_web_search');
    expect(answer.generatedAt, DateTime.utc(2026, 7, 24, 20));
    expect(answer.answerText, contains('Flutter builds multiplatform'));
    expect(answer.answerText, contains('written in Dart'));
    expect(answer.citations, hasLength(2));
    expect(answer.citations.first.url, 'https://docs.flutter.dev');
    expect(answer.citations.first.position, 1);
    expect(answer.citations.last.position, 2);
  });

  test('returns null without a stored API key', () async {
    var networkCalled = false;
    final provider = BraveSearchGroundedAnswerProvider(
      settings: configured,
      apiKeyLoader: () async => '   ',
      httpClient: MockClient((request) async {
        networkCalled = true;
        return http.Response('{}', 200);
      }),
    );

    expect(await provider.fetchGroundedAnswer('question'), isNull);
    expect(networkCalled, isFalse);
  });

  test('returns null when Brave returns no usable results', () async {
    final provider = BraveSearchGroundedAnswerProvider(
      settings: configured,
      apiKeyLoader: () async => 'key',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'web': {
              'results': [
                {
                  'url': '',
                  'title': 'Incomplete',
                  'description': 'No source URL.',
                },
              ],
            },
          }),
          200,
        ),
      ),
    );

    expect(await provider.fetchGroundedAnswer('question'), isNull);
  });

  test('blank questions never call Brave', () async {
    var networkCalled = false;
    final provider = BraveSearchGroundedAnswerProvider(
      settings: configured,
      apiKeyLoader: () async => 'key',
      httpClient: MockClient((request) async {
        networkCalled = true;
        return http.Response('{}', 200);
      }),
    );

    expect(await provider.fetchGroundedAnswer('   '), isNull);
    expect(networkCalled, isFalse);
  });
}
