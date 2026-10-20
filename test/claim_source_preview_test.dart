import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/selected_claims_draft_builder.dart';
import 'package:grepink/widgets/claim_review_groups_panel.dart';
import 'package:grepink/widgets/claim_source_preview.dart';

ClaimReviewItem item(String id, List<String> urls) => ClaimReviewItem(
      id: id,
      text: 'Claim $id',
      classification: ClaimNoveltyClassification.newClaim,
      citationUrls: urls,
      citationTitles: const [],
      selectedByDefault: true,
      reason: '',
      matchedLocalEvidenceIds: const [],
      canBeSaved: true,
    );

const citations = [
  GroundedAnswerCitation(
    id: 'a',
    title: 'First page',
    url: 'https://example.com/a',
    snippet:
        'Original source sentence. Another source sentence. A third sentence.',
  ),
  GroundedAnswerCitation(
    id: 'duplicate',
    title: 'Duplicate',
    url: 'https://example.com/a',
  ),
  GroundedAnswerCitation(
    id: 'b',
    title: 'Second page',
    url: 'https://example.com/b',
    snippet: 'Different source text.',
  ),
];

Future<void> pumpPanel(
  WidgetTester tester,
  List<ClaimReviewItem> items, {
  ValueChanged<String>? toggle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClaimReviewGroupsPanel(
            groups: [
              ClaimReviewGroup(
                label: 'New claims',
                classification: ClaimNoveltyClassification.newClaim,
                items: items,
              ),
            ],
            selectedIds: items.map((i) => i.id).toSet(),
            onToggle: toggle ?? (_) {},
            citations: citations,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('deduplicates presentation without removing saved URLs', () {
    final claim = item('one', [
      'https://example.com/a',
      'https://example.com/a',
      'https://example.com/b',
    ]);
    final previews = claimSourcePreviews(claim, citations);
    expect(previews.length, 2);
    expect(
      previews.first.excerpt,
      'Original source sentence. Another source sentence.',
    );
    expect(claim.citationUrls.length, 3);
    final draft = const SelectedClaimsDraftBuilder().build(
      question: 'Question',
      selected: [claim],
      providerName: 'Brave',
      citations: citations,
    );
    expect(draft.markdownContent, contains('https://example.com/a'));
    expect(draft.markdownContent, contains('https://example.com/b'));
    expect(draft.sourceCount, 2);
  });

  test('missing excerpt is not replaced by generated claim text', () {
    final source = claimSourcePreviews(
      item('one', ['https://example.com/unknown']),
      citations,
    ).single;
    expect(source.excerpt, isNull);
    expect(source.title, 'example.com');
    expect(source.pageLink, 'https://example.com/unknown');
  });

  test(
    'highlight link encodes source text and retains original page anchor',
    () {
      const source = ClaimSourcePreview(
        'https://example.com/a?x=1#section',
        'Page',
        'Exact source & more.',
      );
      final parsed = Uri.parse(source.pageLink);
      expect(parsed.host, 'example.com');
      expect(parsed.query, 'x=1');
      expect(
        Uri.decodeComponent(parsed.fragment),
        'section:~:text=Exact source & more.',
      );
      expect(source.url, 'https://example.com/a?x=1#section');
    },
  );

  test('excerpts are limited to two sentences and bounded length', () {
    expect(sourceExcerpt('One. Two. Three.'), 'One. Two.');
    expect(sourceExcerpt('x' * 1000).length, 360);
  });

  test('structured excerpts retain headings, lists and tables', () {
    const markdown = '## Types\n\n- **Integer**\n- `float`\n\n'
        '| Type | Size |\n| --- | --- |\n| int | 32 |';
    expect(sourceExcerpt(markdown), markdown);
    expect(
        sourcePlainText(
            '## **Types**\n\n- `int` and [float](https://example.com)'),
        'Types int and float');
    const source = ClaimSourcePreview(
        'https://example.com', 'Types', '**Integer** and `float`.');
    expect(Uri.decodeComponent(Uri.parse(source.pageLink).fragment),
        ':~:text=Integer and float.');
    final clipped = sourceExcerpt('```dart\n${'long line\n' * 300}');
    expect(clipped, endsWith('```\n\n…'));
  });

  testWidgets('Markdown claim keeps selection working and renders styled spans',
      (tester) async {
    final toggles = <String>[];
    const claim = ClaimReviewItem(
      id: 'styled',
      text: '**Bold claim** with `code` and *emphasis*',
      classification: ClaimNoveltyClassification.newClaim,
      citationUrls: ['https://example.com/a'],
      citationTitles: [],
      selectedByDefault: true,
      reason: '',
      matchedLocalEvidenceIds: [],
      canBeSaved: true,
    );
    await pumpPanel(tester, [claim], toggle: toggles.add);
    final tile = find.byKey(const Key('claim-review-item-styled'));
    expect(find.descendant(of: tile, matching: find.byType(MarkdownBody)),
        findsOneWidget);
    final spans = tester
        .widgetList<RichText>(
            find.descendant(of: tile, matching: find.byType(RichText)))
        .map((widget) => widget.text.toPlainText())
        .join(' ');
    expect(spans, contains('Bold claim'));
    expect(spans, isNot(contains('**')));
    await tester
        .tap(find.descendant(of: tile, matching: find.byType(Checkbox)));
    await tester.pump();
    expect(toggles, ['styled']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'source pane renders headings, tables and code without fetching images',
      (tester) async {
    const snippet = '## Types\n\n**Bold** and *italic* with `code`.\n\n'
        '- First\n- Second\n\n'
        '| Type | Size |\n| --- | --- |\n| int | 32 |\n\n'
        '![Illustration](https://example.com/image.png)';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 380,
      child: SingleChildScrollView(
          child: ClaimSourcePreviewPane(
        item: item('one', ['https://example.com/a']),
        citations: const [
          GroundedAnswerCitation(
              id: 'a',
              title: 'Page',
              url: 'https://example.com/a',
              snippet: snippet)
        ],
        onClose: () {},
      )),
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Illustration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tap opens excerpts without changing claim selection; close removes overlay',
    (tester) async {
      final toggles = <String>[];
      await pumpPanel(
          tester,
          [
            item('one', ['https://example.com/a', 'https://example.com/a']),
          ],
          toggle: toggles.add);
      expect(find.text('1 source'), findsOneWidget);
      expect(find.text('https://example.com/a'), findsNothing);
      expect(find.byKey(const Key('source-preview-pane')), findsNothing);
      await tester.tap(find.byKey(const Key('claim-review-sources-one')));
      await tester.pumpAndSettle();
      expect(
        find.text('Original source sentence. Another source sentence.'),
        findsOneWidget,
      );
      expect(toggles, isEmpty);
      await tester.tap(find.byTooltip('Close source preview'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-preview-pane')), findsNothing);
    },
  );

  testWidgets(
    'pinned pane follows the hovered claim and stays open after leaving it',
    (tester) async {
      await pumpPanel(tester, [
        item('one', ['https://example.com/a']),
        item('two', ['https://example.com/b']),
      ]);
      await tester.tap(find.byKey(const Key('pin-source-preview')));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getTopLeft(find.byKey(const Key('claim-review-item-one'))) +
            const Offset(8, 8),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Original source sentence. Another source sentence.'),
        findsOneWidget,
      );
      await mouse.moveTo(
        tester.getTopLeft(find.byKey(const Key('claim-review-item-two'))) +
            const Offset(8, 8),
      );
      await tester.pumpAndSettle();
      expect(find.text('Different source text.'), findsOneWidget);
      expect(
        find.text('Original source sentence. Another source sentence.'),
        findsNothing,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('source-preview-pane')), findsOneWidget);
    },
  );

  testWidgets('new review does not show a previous claim in the pinned pane', (
    tester,
  ) async {
    await pumpPanel(tester, [
      item('old', ['https://example.com/a']),
    ]);
    await tester.tap(find.byKey(const Key('claim-review-sources-old')));
    await tester.pumpAndSettle();
    await pumpPanel(tester, [
      item('new', ['https://example.com/b']),
    ]);
    await tester.pumpAndSettle();
    expect(
      find.text('Original source sentence. Another source sentence.'),
      findsNothing,
    );
  });
}
