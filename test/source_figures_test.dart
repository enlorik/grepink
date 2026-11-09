import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grepink/services/source_page_loader.dart';
import 'package:grepink/services/source_image_loader.dart';
import 'package:grepink/widgets/source_page_reader.dart';
import 'package:grepink/widgets/source_figure.dart';
import 'package:grepink/widgets/note_reading_view.dart';
import 'article_figure_fixture.dart';

class _PageLoader implements SourcePageLoader {
  final SourcePage page;
  _PageLoader(this.page);
  @override
  Future<SourcePage> load(String url) async => page;
}

class _Images implements SourceImageLoader {
  @override
  Future<Uint8List> load(String url) async => articleFigureBytes();
}

final article = parseSourcePage(
  '''<title>Tuple field guide</title><main><h1>Tuple fields</h1><p>A tuple holds distinct fields.</p><figure><img src="/diagram.png" width="840" height="264" alt="Tuple fields"><figcaption>Two distinct fields grouped in a tuple.</figcaption></figure><p>Each field keeps its own type.</p><img src="/tracking.gif" width="1" height="1" alt="Tracking pixel"></main>''',
  baseUrl: Uri.parse('https://example.com/guide'),
);

void main() {
  test(
    'page extraction resolves useful article figures and excludes tracking images',
    () {
      expect(article.images.single.url, 'https://example.com/diagram.png');
      expect(article.images.single.caption, contains('Two distinct fields'));
      expect(article.excerptIndex('A tuple holds distinct fields.'), 1);
      expect(article.excerptIndex('Unrelated invented words.'), isNull);
      expect(article.candidateIndex('Other unrelated science.'), isNull);
      expect(sourceTextKey('C# and snake_case'), 'c# and snake_case');
    },
  );
  test(
    'image adapter bounds downloads and rejects private redirects without credentials',
    () async {
      var calls = 0;
      final loader = HttpSourceImageLoader(
        clientFactory: () => MockClient((request) async {
          calls++;
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.body, isEmpty);
          return http.Response.bytes(
            articleFigureBytes(),
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      await loader.load('https://example.com/diagram.png');
      await loader.load('https://example.com/diagram.png');
      expect(calls, 1);
      await expectLater(
        loader.load('http://127.0.0.1/image.png'),
        throwsA(isA<SourcePageException>()),
      );
      final redirect = HttpSourceImageLoader(
        clientFactory: () => MockClient(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'http://10.0.0.1/image.png'},
          ),
        ),
      );
      await expectLater(
        redirect.load('https://example.com/redir'),
        throwsA(isA<SourcePageException>()),
      );
      final oversized = HttpSourceImageLoader(
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes(
            Uint8List(2500001),
            200,
            headers: {'content-type': 'image/png'},
          ),
        ),
      );
      await expectLater(
        oversized.load('https://example.com/big.png'),
        throwsA(isA<SourcePageException>()),
      );
    },
  );
  testWidgets(
    'cited excerpt is located and highlighted with its article figure',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final output = Platform.environment['GREPINK_LAYOUT_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(
            await File(
              Platform.environment['GREPINK_PREVIEW_FONT']!,
            ).readAsBytes(),
          );
          await (FontLoader('Inter')..addFont(Future.value(bytes))).load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Inter'),
            home: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: NoteReadingView(
                      content:
                          '# Rust\n\n## Tuples, at a glance\n\nA tuple groups values with different types into one fixed-size value.\n\n- **Fields keep their own types**, so a name and a count can live together.\n- Access fields by position: `value.0` and `value.1`.\n\n### A small example\n\n```rust\nlet item: (&str, u32) = ("paper", 24);\nlet count = item.1;\n```\n\n![Two distinct tuple fields](https://example.com/diagram.png)\n\nChoose tuples for short groups of values; name longer-lived structures with a struct.',
                      imageLoader: _Images(),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 500,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SourcePageReader(
                        url: 'https://example.com/guide',
                        passage: 'Tuples group distinct fields.',
                        savedExcerpt: 'A tuple holds distinct fields.',
                        loader: _PageLoader(article),
                        imageLoader: _Images(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('provider-cited-excerpt')), findsOneWidget);
      expect(find.byKey(const Key('page-passage-highlight')), findsNothing);
      await tester.tap(find.text('Read article context'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-passage-highlight')), findsOneWidget);
      expect(find.byType(SourceFigure), findsNWidgets(2));
      expect(find.byType(Image), findsNWidgets(2));
      // Decode the exact provider used by the widget before capturing pixels.
      final renderedImage = tester.widget<Image>(find.byType(Image).last);
      await tester.runAsync(
        () => precacheImage(
          renderedImage.image,
          tester.element(find.byType(Image).last),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          tester.widget<Image>(find.byType(Image).first).image,
          tester.element(find.byType(Image).first),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cited text located in this page'), findsOneWidget);
      if (output != null) {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${File(output).parent.path}/cited-figure-workspace.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a keyword match is labeled unverified and never a cited quote', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourcePageReader(
              url: 'https://example.com/guide',
              passage: 'A tuple holds distinct fields.',
              loader: _PageLoader(article),
              imageLoader: _Images(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('provider-cited-excerpt')), findsNothing);
    expect(
      find.text('Related page text · not verified evidence'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('missing-cited-excerpt')), findsOneWidget);
  });
  testWidgets('an unmatched excerpt does not hide available article figures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourcePageReader(
              url: 'https://example.com/guide',
              passage: 'Unrelated material.',
              savedExcerpt: 'A quote absent from this page.',
              loader: _PageLoader(article),
              imageLoader: _Images(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SourceFigure), findsOneWidget);
    expect(find.byKey(const Key('no-page-match')), findsOneWidget);
    expect(find.byKey(const Key('page-passage-highlight')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
