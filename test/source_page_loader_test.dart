import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grepink/services/source_page_loader.dart';

void main() {
  test('extracts real article formatting and matches the passage locally', () {
    final page = parseSourcePage(
      '<title>Rust reference</title><nav>Noise</nav><main><h1>Types</h1><p>Scalar numbers.</p><h2 id="functions">Function types</h2><p><strong>Function pointers</strong> implement <code>Fn</code>.</p><script>bad()</script><img src="https://track.example/image"></main>',
    );
    expect(page.title, 'Rust reference');
    expect(
      page.sections[page.relevantIndex('Function pointers implement Fn')].text,
      contains('Function pointers'),
    );
    expect(
      page.sections[page.relevantIndex('anything', anchor: 'functions')].anchor,
      'functions',
    );
    expect(page.contextAt(3), contains('**Function pointers**'));
    expect(
      page.sections.map((s) => s.markdown).join(),
      isNot(contains('Noise')),
    );
    expect(
      page.sections.map((s) => s.markdown).join(),
      isNot(contains('track.example')),
    );
  });
  test(
    'coalesces downloads, preserves query, strips fragments and sends no credentials or note text',
    () async {
      var requests = 0;
      final loader = HttpSourcePageLoader(
        clientFactory: () => MockClient((request) async {
          requests++;
          expect(request.url.toString(), 'https://example.com/page?lang=en');
          expect(
            request.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(request.body, isEmpty);
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return http.Response(
            '<main><p>Evidence.</p></main>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );
      final both = await Future.wait([
        loader.load('https://example.com/page?lang=en#a'),
        loader.load('https://example.com/page?lang=en#b'),
      ]);
      expect(requests, 1);
      expect(identical(both.first, both.last), isTrue);
      await loader.load('https://example.com/page?lang=en');
      expect(requests, 1);
    },
  );
  test(
    'rejects private endpoints before requesting and validates redirects',
    () async {
      var calls = 0;
      final loader = HttpSourcePageLoader(
        clientFactory: () => MockClient((request) async {
          calls++;
          return http.Response(
            '',
            302,
            headers: {'location': 'http://169.254.169.254/latest/meta-data'},
          );
        }),
      );
      for (final url in [
        'http://127.0.0.1',
        'http://127.1',
        'http://2130706433',
        'http://10.0.0.1',
        'http://192.168.1.2',
        'http://localhost',
        'file:///tmp/test',
        'https://name:secret@example.com',
      ]) {
        await expectLater(
          loader.load(url),
          throwsA(isA<SourcePageException>()),
        );
      }
      expect(calls, 0);
      await expectLater(
        loader.load('https://example.com/redirect'),
        throwsA(isA<SourcePageException>()),
      );
      expect(calls, 1);
    },
  );
  test('failed page can retry and size and type limits are enforced', () async {
    var calls = 0;
    final loader = HttpSourcePageLoader(
      clientFactory: () => MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('Unavailable', 503);
        return http.Response('<main><p>Recovered evidence.</p></main>', 200);
      }),
    );
    await expectLater(
      loader.load('https://example.com'),
      throwsA(isA<SourcePageException>()),
    );
    expect(
      (await loader.load('https://example.com')).sections.single.text,
      'Recovered evidence.',
    );
    final binary = HttpSourcePageLoader(
      clientFactory: () => MockClient(
        (_) async => http.Response(
          'PDF',
          200,
          headers: {'content-type': 'application/pdf'},
        ),
      ),
    );
    await expectLater(
      binary.load('https://example.com/file'),
      throwsA(isA<SourcePageException>()),
    );
    final large = HttpSourcePageLoader(
      clientFactory: () => MockClient(
        (_) async =>
            http.Response('x' * (HttpSourcePageLoader.maxBytes + 1), 200),
      ),
    );
    await expectLater(
      large.load('https://example.com/large'),
      throwsA(isA<SourcePageException>()),
    );
  });
  test('timeout fails without an endless retry loop', () async {
    final loader = HttpSourcePageLoader(
      timeout: const Duration(milliseconds: 5),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(
      loader.load('https://example.com'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
