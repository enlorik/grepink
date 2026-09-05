import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/railway_http_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MockClient _mockClient({
  int statusCode = 200,
  String body = '{"acknowledged":[],"conflicts":[],"snapshot":[]}',
  Duration? delay,
}) {
  return MockClient((request) async {
    if (delay != null) await Future.delayed(delay);
    return http.Response(body, statusCode);
  });
}

const _baseUrl = 'https://test.railway.app';
const _token = 'test-token';

void main() {
  // ---------------------------------------------------------------------------
  // checkHealth
  // ---------------------------------------------------------------------------

  group('checkHealth', () {
    test('returns true when server returns 200', () async {
      final client = LiveRailwayHttpClient(
        client: MockClient((_) async => http.Response('{"ok":true}', 200)),
      );
      expect(await client.checkHealth(_baseUrl), isTrue);
    });

    test('returns false when server returns 503', () async {
      final client = LiveRailwayHttpClient(
        client: MockClient((_) async => http.Response('{"ok":false}', 503)),
      );
      expect(await client.checkHealth(_baseUrl), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Authorization header
  // ---------------------------------------------------------------------------

  group('sync headers', () {
    test('sends Bearer token in Authorization header', () async {
      String? capturedAuth;
      final client = LiveRailwayHttpClient(
        client: MockClient((request) async {
          capturedAuth = request.headers['authorization'];
          return http.Response(
              '{"acknowledged":[],"conflicts":[],"snapshot":[]}', 200);
        }),
      );
      await client.sync(_baseUrl, _token, []);
      expect(capturedAuth, 'Bearer $_token');
    });

    test('sends Content-Type: application/json', () async {
      String? capturedContentType;
      final client = LiveRailwayHttpClient(
        client: MockClient((request) async {
          capturedContentType = request.headers['content-type'];
          return http.Response(
              '{"acknowledged":[],"conflicts":[],"snapshot":[]}', 200);
        }),
      );
      await client.sync(_baseUrl, _token, []);
      expect(capturedContentType, contains('application/json'));
    });

    test('request body is valid JSON with mutations key', () async {
      String? capturedBody;
      final client = LiveRailwayHttpClient(
        client: MockClient((request) async {
          capturedBody = request.body;
          return http.Response(
              '{"acknowledged":[],"conflicts":[],"snapshot":[]}', 200);
        }),
      );
      final mutations = [
        {'mutationId': 'abc', 'noteId': 'xyz', 'operation': 'upsert'},
      ];
      await client.sync(_baseUrl, _token, mutations);
      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(decoded['mutations'], isA<List>());
      expect((decoded['mutations'] as List).length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  group('sync response parsing', () {
    test('parses acknowledged mutations', () async {
      final body = jsonEncode({
        'acknowledged': [
          {'mutationId': 'mid1', 'noteId': 'nid1', 'revision': 42}
        ],
        'conflicts': [],
        'snapshot': [],
      });
      final client = LiveRailwayHttpClient(client: _mockClient(body: body));
      final resp = await client.sync(_baseUrl, _token, []);
      expect(resp.acknowledged.length, 1);
      expect(resp.acknowledged[0].mutationId, 'mid1');
      expect(resp.acknowledged[0].revision, 42);
    });

    test('parses conflicts', () async {
      final body = jsonEncode({
        'acknowledged': [],
        'conflicts': [
          {
            'mutationId': 'mid2',
            'noteId': 'nid2',
            'operation': 'upsert',
            'serverRevision': 7,
            'serverState': {
              'title': 'Remote version',
              'content': 'content',
              'tags': <String>[],
              'keywords': <String>[],
              'isPinned': false,
              'createdAt': '2026-01-01T00:00:00.000Z',
              'updatedAt': '2026-01-01T00:00:00.000Z',
            },
          }
        ],
        'snapshot': [],
      });
      final client = LiveRailwayHttpClient(client: _mockClient(body: body));
      final resp = await client.sync(_baseUrl, _token, []);
      expect(resp.conflicts.length, 1);
      expect(resp.conflicts[0].serverRevision, 7);
      expect(resp.conflicts[0].serverState?['title'], 'Remote version');
    });

    test('parses snapshot rows including tombstones', () async {
      final body = jsonEncode({
        'acknowledged': [],
        'conflicts': [],
        'snapshot': [
          {
            'id': 'note1',
            'revision': 3,
            'deleted': false,
            'title': 'Hello',
            'content': 'World',
            'tags': <String>[],
            'keywords': <String>[],
            'isPinned': false,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'updatedAt': '2026-01-01T00:00:00.000Z',
          },
          {
            'id': 'deleted1',
            'revision': 5,
            'deleted': true,
            'title': null,
            'content': null,
            'tags': <String>[],
            'keywords': <String>[],
            'isPinned': false,
            'createdAt': null,
            'updatedAt': null,
          }
        ],
      });
      final client = LiveRailwayHttpClient(client: _mockClient(body: body));
      final resp = await client.sync(_baseUrl, _token, []);
      expect(resp.snapshot.length, 2);
      expect(resp.snapshot[0].deleted, isFalse);
      expect(resp.snapshot[0].title, 'Hello');
      expect(resp.snapshot[1].deleted, isTrue);
      expect(resp.snapshot[1].title, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Error handling
  // ---------------------------------------------------------------------------

  group('error handling', () {
    test('401 throws RailwayAuthException', () async {
      final client = LiveRailwayHttpClient(
        client: _mockClient(statusCode: 401, body: '{"error":"Unauthorized"}'),
      );
      expect(
        () => client.sync(_baseUrl, _token, []),
        throwsA(isA<RailwayAuthException>()),
      );
    });

    test('413 throws RailwayRequestTooLargeException', () async {
      final client = LiveRailwayHttpClient(
        client: _mockClient(statusCode: 413, body: '{"error":"Too large"}'),
      );
      expect(
        () => client.sync(_baseUrl, _token, []),
        throwsA(isA<RailwayRequestTooLargeException>()),
      );
    });

    test('500 throws RailwayServerException', () async {
      final client = LiveRailwayHttpClient(
        client: _mockClient(statusCode: 500, body: '{"error":"Server error"}'),
      );
      expect(
        () => client.sync(_baseUrl, _token, []),
        throwsA(isA<RailwayServerException>()),
      );
    });

    test('malformed response throws FormatException', () async {
      final client = LiveRailwayHttpClient(
        client: _mockClient(body: '[1,2,3]'),
      );
      expect(
        () => client.sync(_baseUrl, _token, []),
        throwsA(isA<FormatException>()),
      );
    });

    test('non-JSON response throws', () async {
      final client = LiveRailwayHttpClient(
        client: _mockClient(body: 'not json at all'),
      );
      expect(() => client.sync(_baseUrl, _token, []), throwsA(anything));
    });
  });
}
