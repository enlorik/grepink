import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Minimal fake HTTP client
// ---------------------------------------------------------------------------

class _FakeHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest) _handler;

  _FakeHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

http.Response _braveResponse(List<Map<String, dynamic>> results,
    {int statusCode = 200}) {
  final body = jsonEncode({
    'web': {'results': results},
  });
  return http.Response(body, statusCode,
      headers: {'content-type': 'application/json'});
}

BraveEvidenceProvider _provider(
  Future<http.Response> Function(http.BaseRequest) handler, {
  int count = 5,
  String? country,
  BraveSafeSearch safeSearch = BraveSafeSearch.moderate,
}) {
  return BraveEvidenceProvider(
    apiKey: 'test-key',
    httpClient: _FakeHttpClient(handler),
    count: count,
    country: country,
    safeSearch: safeSearch,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('BraveEvidenceProvider – basic fetch', () {
    test('returns EvidenceItems from API results', () async {
      final provider = _provider((_) async => _braveResponse([
            {
              'title': 'Photosynthesis Overview',
              'url': 'https://example.com/photosynthesis',
              'description': 'Plants convert sunlight into glucose.',
            },
            {
              'title': 'Chlorophyll Role',
              'url': 'https://example.com/chlorophyll',
              'description': 'Chlorophyll absorbs light energy.',
            },
          ]));

      final results = await provider.fetch('What is photosynthesis?');

      expect(results, hasLength(2));
      expect(results[0].type, EvidenceType.webSearch);
      expect(results[0].title, 'Photosynthesis Overview');
      expect(results[0].content, 'Plants convert sunlight into glucose.');
      expect(results[0].sourceUrl, 'https://example.com/photosynthesis');
      expect(results[1].title, 'Chlorophyll Role');
    });

    test('empty question returns empty list without HTTP call', () async {
      var called = false;
      final provider = _provider((_) async {
        called = true;
        return _braveResponse([]);
      });

      final results = await provider.fetch('   ');

      expect(results, isEmpty);
      expect(called, isFalse);
    });

    test('empty web results returns empty list', () async {
      final provider = _provider((_) async => _braveResponse([]));

      final results = await provider.fetch('obscure query');

      expect(results, isEmpty);
    });

    test('missing web block returns empty list', () async {
      final provider = _provider((_) async => http.Response(
            jsonEncode(<String, dynamic>{}),
            200,
            headers: {'content-type': 'application/json'},
          ));

      final results = await provider.fetch('query');

      expect(results, isEmpty);
    });
  });

  group('BraveEvidenceProvider – EvidenceItem shape', () {
    test('each item has a unique id', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'A', 'url': 'https://a.com', 'description': 'desc a'},
            {'title': 'B', 'url': 'https://b.com', 'description': 'desc b'},
          ]));

      final results = await provider.fetch('q');
      final ids = results.map((e) => e.id).toSet();

      expect(ids, hasLength(results.length));
    });

    test('missing description is skipped', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'No desc', 'url': 'https://a.com'},
          ]));

      final results = await provider.fetch('q');

      expect(results, isEmpty);
    });

    test('blank description is skipped', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'Blank desc', 'url': 'https://a.com', 'description': '   '},
          ]));

      final results = await provider.fetch('q');

      expect(results, isEmpty);
    });

    test('missing url is skipped', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'No URL', 'description': 'Some description'},
          ]));

      final results = await provider.fetch('q');

      expect(results, isEmpty);
    });

    test('blank url is skipped', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'Blank URL', 'url': '   ', 'description': 'Some description'},
          ]));

      final results = await provider.fetch('q');

      expect(results, isEmpty);
    });

    test('missing title is skipped', () async {
      final provider = _provider((_) async => _braveResponse([
            {'url': 'https://a.com', 'description': 'desc'},
          ]));

      final results = await provider.fetch('q');

      expect(results, isEmpty);
    });

    test('blank title is skipped', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': '   ', 'url': 'https://a.com', 'description': 'desc'},
          ]));

      final results = await provider.fetch('q');

      expect(results, isEmpty);
    });

    test('only valid entries are returned when mixed with invalid ones', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'Valid', 'url': 'https://a.com', 'description': 'good desc'},
            {'title': 'No URL', 'description': 'missing url'},
            {'title': 'Also Valid', 'url': 'https://b.com', 'description': 'also good'},
          ]));

      final results = await provider.fetch('q');

      expect(results, hasLength(2));
      expect(results[0].title, 'Valid');
      expect(results[1].title, 'Also Valid');
    });

    test('relevanceScore is assigned in descending order', () async {
      final provider = _provider((_) async => _braveResponse([
            {'title': 'First', 'url': 'https://a.com', 'description': 'desc a'},
            {'title': 'Second', 'url': 'https://b.com', 'description': 'desc b'},
            {'title': 'Third', 'url': 'https://c.com', 'description': 'desc c'},
          ]));

      final results = await provider.fetch('q');

      expect(results[0].relevanceScore, closeTo(1.0, 0.001));
      expect(results[1].relevanceScore, closeTo(0.9, 0.001));
      expect(results[2].relevanceScore, closeTo(0.8, 0.001));
      expect(results[0].relevanceScore,
          greaterThan(results[1].relevanceScore));
      expect(results[1].relevanceScore,
          greaterThan(results[2].relevanceScore));
    });
  });

  group('BraveEvidenceProvider – HTTP request details', () {
    test('sends correct API key header', () async {
      http.BaseRequest? captured;
      final provider = _provider((req) async {
        captured = req;
        return _braveResponse([]);
      });

      await provider.fetch('test');

      expect(captured?.headers['X-Subscription-Token'], 'test-key');
    });

    test('sends count as query parameter', () async {
      Uri? capturedUri;
      final provider = _provider((req) async {
            capturedUri = req.url;
            return _braveResponse([]);
          },
          count: 3);

      await provider.fetch('test');

      expect(capturedUri?.queryParameters['count'], '3');
    });

    test('clamps count to maximum of 20', () async {
      Uri? capturedUri;
      final provider = _provider((req) async {
            capturedUri = req.url;
            return _braveResponse([]);
          },
          count: 99);

      await provider.fetch('test');

      expect(capturedUri?.queryParameters['count'], '20');
    });

    test('sends country when configured', () async {
      Uri? capturedUri;
      final provider = _provider((req) async {
            capturedUri = req.url;
            return _braveResponse([]);
          },
          country: 'US');

      await provider.fetch('test');

      expect(capturedUri?.queryParameters['country'], 'US');
    });

    test('omits country when not configured', () async {
      Uri? capturedUri;
      final provider = _provider((req) async {
        capturedUri = req.url;
        return _braveResponse([]);
      });

      await provider.fetch('test');

      expect(capturedUri?.queryParameters.containsKey('country'), isFalse);
    });

    test('sends safesearch parameter', () async {
      Uri? capturedUri;
      final provider = _provider((req) async {
            capturedUri = req.url;
            return _braveResponse([]);
          },
          safeSearch: BraveSafeSearch.strict);

      await provider.fetch('test');

      expect(capturedUri?.queryParameters['safesearch'], 'strict');
    });

    test('default safesearch is moderate', () async {
      Uri? capturedUri;
      final provider = _provider((req) async {
        capturedUri = req.url;
        return _braveResponse([]);
      });

      await provider.fetch('test');

      expect(capturedUri?.queryParameters['safesearch'], 'moderate');
    });
  });

  group('BraveEvidenceProvider – error handling', () {
    test('empty API key returns empty list without HTTP call', () async {
      var called = false;
      final provider = BraveEvidenceProvider(
        apiKey: '   ',
        httpClient: _FakeHttpClient((_) async {
          called = true;
          return _braveResponse([]);
        }),
      );

      final results = await provider.fetch('test');

      expect(results, isEmpty);
      expect(called, isFalse);
    });

    test('non-200 response returns empty list', () async {
      final provider = _provider((_) async => http.Response(
            '{"error":"unauthorized"}',
            401,
            headers: {'content-type': 'application/json'},
          ));

      final results = await provider.fetch('test');

      expect(results, isEmpty);
    });

    test('malformed JSON returns empty list', () async {
      final provider = _provider((_) async => http.Response(
            'not-valid-json{{{',
            200,
            headers: {'content-type': 'application/json'},
          ));

      final results = await provider.fetch('test');

      expect(results, isEmpty);
    });

    test('network exception returns empty list', () async {
      final provider = _provider((_) async => throw Exception('Network error'));

      final results = await provider.fetch('test');

      expect(results, isEmpty);
    });

    test('BraveApiException toString includes status code', () {
      const ex = BraveApiException(statusCode: 429, body: 'rate limited');
      expect(ex.toString(), contains('429'));
    });
  });
}
