import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/source_page_loader.dart';
import 'package:grepink/widgets/note_reading_view.dart';
import 'package:grepink/widgets/source_page_reader.dart';

class _Pages implements SourcePageLoader {
  final SourcePage page;
  const _Pages(this.page);
  @override
  Future<SourcePage> load(String url) async => page;
}

void main() {
  test(
    'article extraction keeps semantic tables, lazy figures and real titles',
    () {
      final page = parseSourcePage(
        '''<title>Site boilerplate</title><main><p>Navigation introduction.</p><article><header><h1>A field guide</h1></header><p>Distinct Rust tuple fields.</p><figure><a href="/large"><img src="/placeholder.gif" srcset="/small.png 320w, /medium.png 800w, /huge.png 2400w" width="800" height="300"></a><figcaption>Two tuple fields.</figcaption></figure><table><tr><th>Field</th><th>Type</th></tr><tr><td>first</td><td><code>u32</code></td></tr></table></article></main>''',
        baseUrl: Uri.parse('https://example.com/article'),
      );
      expect(page.title, 'A field guide');
      expect(
        page.sections.any((s) => s.text.contains('Navigation introduction')),
        isFalse,
      );
      expect(page.images.single.url, 'https://example.com/medium.png');
      expect(page.images.single.caption, 'Two tuple fields.');
      expect(page.sections.last.markdown, contains('| first | `u32` |'));
      expect(page.sections.last.markdown, contains('| --- | --- |'));
    },
  );

  testWidgets('article title replaces raw URL and context is disclosed once', (
    tester,
  ) async {
    final page = parseSourcePage(
      '<title>Article</title><article><h1>Rust tuples</h1><p>A tuple holds <strong>distinct</strong> fields.</p><p>Each field retains a type.</p></article>',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourcePageReader(
              url: 'https://example.com/very/long/url',
              passage: 'A tuple holds distinct fields.',
              savedExcerpt: 'A tuple holds distinct fields.',
              loader: _Pages(page),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rust tuples'), findsOneWidget);
    expect(find.text('https://example.com/very/long/url'), findsNothing);
    expect(find.byKey(const Key('page-passage-highlight')), findsNothing);
    await tester.tap(find.text('Read article context'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-passage-highlight')), findsOneWidget);
    final markdown = tester.widgetList<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.any((w) => w.data.contains('**distinct**')), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notes use a restrained scale and preserve stored Markdown during reading',
    (tester) async {
      const content =
          '# Rust\n\n## Thread safety\n\n- **Ownership** keeps `Send` values safe.\n\nA short paragraph.';
      String? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteReadingView(
              content: content,
              editable: true,
              onChanged: (value) => changed = value,
              onAddBelow: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final markdown = tester.widgetList<MarkdownBody>(
        find.byType(MarkdownBody),
      );
      expect(markdown.first.styleSheet!.h1!.fontSize, 26);
      expect(markdown.first.styleSheet!.p!.height, 1.5);
      expect(changed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long excerpts expand without truncating their stored content', (
    tester,
  ) async {
    final quote = List.filled(30, 'Useful **formatted** excerpt.').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SourcePageReader(
              url: 'https://example.com/guide',
              passage: 'Useful excerpt.',
              savedExcerpt: quote,
              loader: const _Pages(
                SourcePage('Guide', [
                  SourcePageSection(
                    'Unrelated page text.',
                    'Unrelated page text.',
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Full excerpt'), findsOneWidget);
    await tester.tap(find.text('Full excerpt'));
    await tester.pumpAndSettle();
    expect(find.text('Less excerpt'), findsOneWidget);
    expect(
      tester
          .widgetList<MarkdownBody>(find.byType(MarkdownBody))
          .any((w) => w.data == quote),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
